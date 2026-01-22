#!/bin/bash
# ==============================================================================
# DPG Deployment - Progress Bar Utilities
# ==============================================================================
# Functions for progress bar display and terraform apply tracking.
# ==============================================================================

# ==============================================================================
# Draw Progress Bar
# ==============================================================================

# Usage: draw_progress_bar <current> <total> <resource_name> <status>
draw_progress_bar() {
    local current=$1
    local total=$2
    local resource="${3:-Resource}"
    local status="${4:-⏳}"
    local bar_width=40
    
    # Calculate percentage
    local percent=0
    if [[ $total -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi
    
    # Calculate filled width
    local filled=$((current * bar_width / total))
    if [[ $filled -gt $bar_width ]]; then
        filled=$bar_width
    fi
    local empty=$((bar_width - filled))
    
    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    # Color based on progress
    local color=$YELLOW
    if [[ $percent -ge 100 ]]; then
        color=$GREEN
    elif [[ $percent -ge 50 ]]; then
        color=$CYAN
    fi
    
    # Truncate resource name if too long (max 45 chars)
    local resource_display="$resource"
    if [[ ${#resource_display} -gt 45 ]]; then
        resource_display="${resource_display:0:42}..."
    fi
    
    # Print progress bar with resource name prominently displayed
    # Format: [progress_bar] XX% (current/total) | resource_name status
    printf "\r  ${color}[${bar}]${NC} %3d%% (%d/%d) │ ${BOLD}%-45s${NC} %s  " "$percent" "$current" "$total" "$resource_display" "$status"
}

# ==============================================================================
# Terraform Apply with Progress Tracking
# ==============================================================================

terraform_apply_with_progress() {
    local plan_file="$1"
    local log_file="$2"
    
    # Get total resources to create from plan
    local total_resources=$(terraform show -json "$plan_file" 2>/dev/null | \
        grep -o '"create"' | wc -l | tr -d ' ')
    
    if [[ -z "$total_resources" || "$total_resources" -eq 0 ]]; then
        # Fallback: count from plan output
        total_resources=$(terraform show "$plan_file" 2>/dev/null | \
            grep -E "^Plan:" | grep -oE "[0-9]+ to add" | grep -oE "[0-9]+" || echo "0")
    fi
    
    if [[ -z "$total_resources" || "$total_resources" -eq 0 ]]; then
        total_resources=59  # Default fallback
    fi
    
    echo ""
    echo -e "${BOLD}  Deploying $total_resources resources...${NC}"
    echo ""
    
    local created=0
    local current_resource=""
    local current_resource_short=""
    local start_time=$(date +%s)
    
    # Run terraform apply and parse output
    terraform apply -input=false -auto-approve "$plan_file" 2>&1 | while IFS= read -r line; do
        # Log to file
        echo "$line" >> "$log_file"
        
        # Check for resource creation start
        if [[ "$line" =~ Creating\.\.\. ]]; then
            current_resource=$(echo "$line" | grep -oE '^[a-zA-Z_][a-zA-Z0-9_\.\[\]]*' | head -1)
            current_resource_short=$(echo "$current_resource" | sed 's/module\.gpu_infrastructure\.//' | sed 's/module\.[^.]*\.//' | cut -c1-45)
            draw_progress_bar "$created" "$total_resources" "$current_resource_short" "⏳"
        fi
        
        # Check for resource creation complete
        if [[ "$line" =~ Creation\ complete\ after ]]; then
            ((created++))
            local duration_str=$(echo "$line" | grep -oE 'after [0-9]+[ms0-9]*' | sed 's/after //')
            draw_progress_bar "$created" "$total_resources" "$current_resource_short" "✓ (${duration_str})"
        fi
        
        # Check for still creating
        if [[ "$line" =~ Still\ creating\.\.\. ]]; then
            local elapsed=$(echo "$line" | grep -oE '\[[0-9]+[ms0-9]* elapsed\]' | tr -d '[]' | sed 's/ elapsed//')
            if [[ -n "$elapsed" ]]; then
                draw_progress_bar "$created" "$total_resources" "$current_resource_short" "⏳ ${elapsed}"
            else
                draw_progress_bar "$created" "$total_resources" "$current_resource_short" "⏳"
            fi
        fi
        
        # Check for errors
        if [[ "$line" =~ ^╷$ ]] || [[ "$line" =~ ^│\ Error: ]]; then
            echo ""
            echo -e "${RED}$line${NC}"
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo ""
    
    # Check if apply succeeded
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}✓ Deployment completed successfully in ${duration}s${NC}"
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        return 0
    else
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${RED}✗ Deployment failed after ${duration}s${NC}"
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        return 1
    fi
}
