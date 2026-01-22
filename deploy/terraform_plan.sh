#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Plan
# ==============================================================================
# Functions for creating and managing Terraform plans.
# ==============================================================================

# ==============================================================================
# Terraform Plan
# ==============================================================================

terraform_plan() {
    log "STEP" "Creating deployment plan for $PLATFORM..."
    
    cd "$ENV_DIR"
    
    if terraform plan -input=false -out=tfplan 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Deployment plan created"
        return 0
    else
        log "ERROR" "Plan creation failed"
        return 1
    fi
}

# ==============================================================================
# Check Existing Resources
# ==============================================================================

check_existing_resources() {
    log "STEP" "Checking for existing resources..."
    
    cd "$ENV_DIR"
    
    # Get plan summary
    local plan_json=$(terraform show -json tfplan 2>/dev/null)
    
    if [[ -z "$plan_json" ]]; then
        log "WARN" "Could not read plan details"
        return 0
    fi
    
    # Parse resource changes
    local to_create=$(echo "$plan_json" | grep -o '"create"' | wc -l | tr -d ' ')
    local to_update=$(echo "$plan_json" | grep -o '"update"' | wc -l | tr -d ' ')
    local to_replace=$(echo "$plan_json" | grep -o '"delete".*"create"\|"replace"' | wc -l | tr -d ' ')
    local to_destroy=$(echo "$plan_json" | grep -o '"delete"' | wc -l | tr -d ' ')
    
    # Subtract replacements from destroy count (replace = delete + create)
    to_destroy=$((to_destroy - to_replace))
    if [[ $to_destroy -lt 0 ]]; then to_destroy=0; fi
    
    echo ""
    echo -e "${BOLD}  📋 Deployment Plan Summary${NC}"
    echo -e "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}➕ Create:${NC}  $to_create resources"
    
    if [[ $to_update -gt 0 ]]; then
        echo -e "  ${YELLOW}🔄 Update:${NC}  $to_update resources"
    fi
    
    if [[ $to_replace -gt 0 ]]; then
        echo -e "  ${YELLOW}♻️  Replace:${NC} $to_replace resources (destroy & recreate)"
    fi
    
    if [[ $to_destroy -gt 0 ]]; then
        echo -e "  ${RED}➖ Destroy:${NC} $to_destroy resources"
    fi
    
    echo -e "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # If there are updates, replacements, or destroys, ask about them
    if [[ $to_update -gt 0 || $to_replace -gt 0 || $to_destroy -gt 0 ]]; then
        _prompt_for_resource_changes
        return $?
    fi
    
    return 0
}

# ==============================================================================
# Helper: Prompt for Resource Changes
# ==============================================================================

_prompt_for_resource_changes() {
    echo -e "${YELLOW}⚠ Some resources already exist and will be modified:${NC}"
    echo ""
    
    # List resources that will be updated/replaced/destroyed
    local changed_resources=$(terraform show tfplan 2>/dev/null | grep -E "^\s+#.*will be (updated|replaced|destroyed)" | head -20)
    
    if [[ -n "$changed_resources" ]]; then
        echo "$changed_resources" | while read -r line; do
            if [[ "$line" =~ "destroyed" ]]; then
                echo -e "  ${RED}$line${NC}"
            elif [[ "$line" =~ "replaced" ]]; then
                echo -e "  ${YELLOW}$line${NC}"
            else
                echo -e "  ${CYAN}$line${NC}"
            fi
        done
        echo ""
    fi
    
    echo -e "${BOLD}Choose an action:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Apply all changes (update/replace existing resources)"
    echo -e "  ${CYAN}2)${NC} Create only NEW resources (skip existing)"
    echo -e "  ${YELLOW}3)${NC} Show detailed changes"
    echo -e "  ${RED}4)${NC} Cancel deployment"
    echo ""
    
    read -p "Select option [1-4]: " choice
    
    case "$choice" in
        1)
            log "INFO" "Proceeding with all changes..."
            return 0
            ;;
        2)
            log "INFO" "Skipping existing resources, creating new only..."
            create_targeted_plan
            return $?
            ;;
        3)
            echo ""
            terraform show tfplan | head -100
            echo ""
            echo -e "${YELLOW}... (truncated, see full plan with 'terraform show tfplan')${NC}"
            echo ""
            read -p "Press Enter to continue..."
            check_existing_resources  # Recurse to show menu again
            return $?
            ;;
        4)
            log "INFO" "Deployment cancelled by user"
            return 1
            ;;
        *)
            log "WARN" "Invalid option, defaulting to apply all changes"
            return 0
            ;;
    esac
}

# ==============================================================================
# Create Targeted Plan (New Resources Only)
# ==============================================================================

create_targeted_plan() {
    log "INFO" "Creating targeted plan for new resources only..."
    
    cd "$ENV_DIR"
    
    # Get list of resources that will be created (not updated/replaced)
    local new_resources=$(terraform show -json tfplan 2>/dev/null | \
        python3 -c "
import sys, json
try:
    plan = json.load(sys.stdin)
    changes = plan.get('resource_changes', [])
    for r in changes:
        actions = r.get('change', {}).get('actions', [])
        if actions == ['create']:
            print('-target=' + r['address'])
except:
    pass
" 2>/dev/null)
    
    if [[ -z "$new_resources" ]]; then
        log "WARN" "Could not determine new resources, proceeding with full plan"
        return 0
    fi
    
    local target_count=$(echo "$new_resources" | wc -l | tr -d ' ')
    log "INFO" "Targeting $target_count new resources..."
    
    # Create new plan with targets
    local targets=$(echo "$new_resources" | tr '\n' ' ')
    
    if terraform plan -input=false -out=tfplan $targets 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Targeted plan created for new resources only"
        return 0
    else
        log "ERROR" "Failed to create targeted plan"
        return 1
    fi
}
