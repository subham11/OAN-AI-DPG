#!/bin/bash
# ==============================================================================
# AWS Quota Checker and Instance Selector
# ==============================================================================
# Checks AWS quotas and automatically selects best instance type/pricing model
# ==============================================================================

# ==============================================================================
# Simple Print Header
# ==============================================================================

print_header() {
    local title="$1"
    echo ""
    echo "  ══════════════════════════════════════════════════"
    echo "  $title"
    echo "  ══════════════════════════════════════════════════"
    echo ""
}

# ==============================================================================
# Check GPU Instance Quotas
# ==============================================================================

check_gpu_quotas() {
    local region="${1:-us-east-1}"
    local requested_instance="${2:-g5.4xlarge}"
    
    print_header "AWS GPU Instance Quota Check"
    
    log "INFO" "Checking quotas for region: $region"
    log "INFO" "Requested instance type: $requested_instance"
    echo ""
    
    # Get vCPUs required for instance type
    local vcpus_needed
    vcpus_needed=$(get_instance_vcpus "$requested_instance" "$region")
    
    if [[ -z "$vcpus_needed" || "$vcpus_needed" == "0" || "$vcpus_needed" == "None" ]]; then
        log "ERROR" "Could not determine vCPU count for $requested_instance"
        log "WARN" "Instance type may not be available in region $region"
        return 1
    fi
    
    log "INFO" "vCPUs required per instance: $vcpus_needed"
    echo ""
    
    # Check On-Demand quota
    local ondemand_quota
    ondemand_quota=$(check_ondemand_quota "$region")
    
    # Handle empty/None values
    if [[ -z "$ondemand_quota" || "$ondemand_quota" == "None" ]]; then
        ondemand_quota="0"
    fi
    
    # Check Spot quota
    local spot_quota
    spot_quota=$(check_spot_quota "$region")
    
    # Handle empty/None values
    if [[ -z "$spot_quota" || "$spot_quota" == "None" ]]; then
        spot_quota="0"
    fi
    
    # Display results
    print_quota_summary "$ondemand_quota" "$spot_quota" "$vcpus_needed"
    
    # Determine best option
    determine_pricing_model "$ondemand_quota" "$spot_quota" "$vcpus_needed" "$requested_instance"
}

# ==============================================================================
# Get Instance vCPU Count
# ==============================================================================

get_instance_vcpus() {
    local instance_type="$1"
    local region="$2"
    
    local vcpus
    vcpus=$(aws ec2 describe-instance-types \
        --instance-types "$instance_type" \
        --region "$region" \
        --query 'InstanceTypes[0].VCpuInfo.DefaultVCpus' \
        --output text 2>/dev/null)
    
    echo "${vcpus:-0}"
}

# ==============================================================================
# Check On-Demand Quota
# ==============================================================================

check_ondemand_quota() {
    local region="$1"
    local quota_code="L-DB2E81BA"  # Running On-Demand G and VT instances
    
    log "INFO" "Checking On-Demand G instance quota..." >&2
    
    local quota_value
    quota_value=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code "$quota_code" \
        --region "$region" \
        --query 'Quota.Value' \
        --output text 2>/dev/null)
    
    if [[ -z "$quota_value" || "$quota_value" == "None" ]]; then
        quota_value="0"
    fi
    
    echo "$quota_value"
}

# ==============================================================================
# Check Spot Quota
# ==============================================================================

check_spot_quota() {
    local region="$1"
    local quota_code="L-3819A6DF"  # All G and VT Spot Instance Requests
    
    log "INFO" "Checking Spot G instance quota..." >&2
    
    local quota_value
    quota_value=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code "$quota_code" \
        --region "$region" \
        --query 'Quota.Value' \
        --output text 2>/dev/null)
    
    if [[ -z "$quota_value" || "$quota_value" == "None" ]]; then
        quota_value="0"
    fi
    
    echo "$quota_value"
}

# ==============================================================================
# Print Quota Summary
# ==============================================================================

print_quota_summary() {
    local ondemand="${1:-0}"
    local spot="${2:-0}"
    local vcpus_needed="${3:-0}"
    
    # Ensure we have numeric values
    [[ -z "$ondemand" || "$ondemand" == "None" ]] && ondemand="0"
    [[ -z "$spot" || "$spot" == "None" ]] && spot="0"
    [[ -z "$vcpus_needed" || "$vcpus_needed" == "None" ]] && vcpus_needed="0"
    
    echo ""
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  ${CYAN}Quota Status${NC}"
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # On-Demand quota
    printf "  ${BOLD}On-Demand G Instances:${NC} "
    if awk "BEGIN {exit !($ondemand >= $vcpus_needed)}" 2>/dev/null; then
        echo "${GREEN}${ondemand} vCPUs available ✓${NC}"
    elif awk "BEGIN {exit !($ondemand > 0)}" 2>/dev/null; then
        echo "${YELLOW}${ondemand} vCPUs (insufficient, need $vcpus_needed)${NC}"
    else
        echo "${RED}0 vCPUs (not available)${NC}"
    fi
    
    # Spot quota
    printf "  ${BOLD}Spot G Instances:${NC}      "
    if awk "BEGIN {exit !($spot >= $vcpus_needed)}" 2>/dev/null; then
        echo "${GREEN}${spot} vCPUs available ✓${NC}"
    elif awk "BEGIN {exit !($spot > 0)}" 2>/dev/null; then
        echo "${YELLOW}${spot} vCPUs (insufficient, need $vcpus_needed)${NC}"
    else
        echo "${RED}0 vCPUs (not available)${NC}"
    fi
    
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ==============================================================================
# Determine Pricing Model Based on Quotas
# ==============================================================================

determine_pricing_model() {
    local ondemand="${1:-0}"
    local spot="${2:-0}"
    local vcpus_needed="${3:-0}"
    local requested_instance="${4:-g5.4xlarge}"
    
    # Ensure we have numeric values
    [[ -z "$ondemand" || "$ondemand" == "None" ]] && ondemand="0"
    [[ -z "$spot" || "$spot" == "None" ]] && spot="0"
    [[ -z "$vcpus_needed" || "$vcpus_needed" == "None" ]] && vcpus_needed="0"
    
    local can_use_ondemand=false
    local can_use_spot=false
    
    # Check if quotas are sufficient using awk for floating point comparison
    if awk "BEGIN {exit !($ondemand >= $vcpus_needed)}" 2>/dev/null; then
        can_use_ondemand=true
    fi
    
    if awk "BEGIN {exit !($spot >= $vcpus_needed)}" 2>/dev/null; then
        can_use_spot=true
    fi
    
    # Decision logic - prefer Spot for cost savings if available
    if [[ "$can_use_spot" == "true" ]]; then
        log "SUCCESS" "Spot instances available - using Spot pricing (up to 90% savings)"
        USE_SPOT_INSTANCES="true"
        SELECTED_PRICING="spot"
        export USE_SPOT_INSTANCES SELECTED_PRICING
        return 0
        
    elif [[ "$can_use_ondemand" == "true" ]]; then
        log "SUCCESS" "On-Demand instances available - using On-Demand pricing"
        USE_SPOT_INSTANCES="false"
        SELECTED_PRICING="on-demand"
        export USE_SPOT_INSTANCES SELECTED_PRICING
        return 0
        
    else
        # Neither has sufficient quota - need to find alternative
        handle_insufficient_quota "$ondemand" "$spot" "$vcpus_needed" "$requested_instance"
        return $?
    fi
}

# ==============================================================================
# Handle Insufficient Quota
# ==============================================================================

handle_insufficient_quota() {
    local ondemand="$1"
    local spot="$2"
    local vcpus_needed="$3"
    local requested_instance="$4"
    
    log "ERROR" "Insufficient quota for $requested_instance (needs $vcpus_needed vCPUs)"
    echo ""
    
    # Try to find alternative instance types
    local alternatives
    alternatives=$(find_alternative_instances "$ondemand" "$spot" "$REGION")
    
    if [[ -n "$alternatives" ]]; then
        echo "${YELLOW}  Available alternatives:${NC}"
        echo "$alternatives"
        echo ""
        
        # Prompt user to select alternative
        prompt_instance_selection "$alternatives"
        
    else
        # No alternatives - must request quota increase
        show_quota_increase_instructions "$requested_instance" "$vcpus_needed"
        return 1
    fi
}

# ==============================================================================
# Find Alternative Instance Types
# ==============================================================================

find_alternative_instances() {
    local ondemand_quota="$1"
    local spot_quota="$2"
    local region="$3"
    
    # GPU instance types to check (smaller to larger)
    local instance_types=(
        "g4dn.xlarge:4"      # 4 vCPUs, 1x T4 GPU
        "g4dn.2xlarge:8"     # 8 vCPUs, 1x T4 GPU
        "g5.xlarge:4"        # 4 vCPUs, 1x A10G GPU
        "g5.2xlarge:8"       # 8 vCPUs, 1x A10G GPU
    )
    
    local alternatives=""
    
    for item in "${instance_types[@]}"; do
        local instance_type="${item%%:*}"
        local vcpus="${item##*:}"
        
        # Check if instance is available in region
        local available
        available=$(aws ec2 describe-instance-type-offerings \
            --location-type availability-zone \
            --region "$region" \
            --filters "Name=instance-type,Values=$instance_type" \
            --query 'InstanceTypeOfferings[0].InstanceType' \
            --output text 2>/dev/null)
        
        if [[ "$available" == "$instance_type" ]]; then
            # Check if fits in quota using awk
            local pricing_model=""
            
            if awk "BEGIN {exit !($spot_quota >= $vcpus)}"; then
                pricing_model="Spot"
            elif awk "BEGIN {exit !($ondemand_quota >= $vcpus)}"; then
                pricing_model="On-Demand"
            fi
            
            if [[ -n "$pricing_model" ]]; then
                alternatives+="  ${GREEN}✓${NC} $instance_type ($vcpus vCPUs) - $pricing_model\n"
            fi
        fi
    done
    
    echo -e "$alternatives"
}

# ==============================================================================
# Prompt Instance Selection
# ==============================================================================

prompt_instance_selection() {
    local alternatives="$1"
    
    echo "${CYAN}Would you like to:${NC}"
    echo "  1) Use one of the available instance types above"
    echo "  2) Request quota increase for original instance type"
    echo "  3) Cancel deployment"
    echo ""
    
    local choice
    read -p "Select option [1-3]: " choice </dev/tty
    
    case "$choice" in
        1)
            local new_instance
            read -p "Enter instance type (e.g., g4dn.xlarge): " new_instance </dev/tty
            INSTANCE_TYPE="$new_instance"
            export INSTANCE_TYPE
            
            # Re-check quotas for new instance
            check_gpu_quotas "$REGION" "$INSTANCE_TYPE"
            return $?
            ;;
        2)
            show_quota_increase_instructions "$INSTANCE_TYPE" "$vcpus_needed"
            return 1
            ;;
        3)
            log "INFO" "Deployment cancelled by user"
            return 1
            ;;
        *)
            log "ERROR" "Invalid selection"
            return 1
            ;;
    esac
}

# ==============================================================================
# Show Quota Increase Instructions
# ==============================================================================

show_quota_increase_instructions() {
    local instance_type="${1:-unknown}"
    local vcpus_needed="${2:-16}"
    local region="${REGION:-us-east-1}"
    
    echo ""
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  ${YELLOW}Quota Increase Required${NC}"
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Instance Type: ${BOLD}$instance_type${NC}"
    echo "  Required vCPUs: ${BOLD}$vcpus_needed${NC} (for 1 instance)"
    echo "  Recommended Request: ${BOLD}64 vCPUs${NC} (allows 4 instances)"
    echo ""
    echo "  ${CYAN}Option 1: AWS Console${NC}"
    echo "  1. Go to: ${BLUE}https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas${NC}"
    echo "  2. Search for: ${BOLD}Running On-Demand G and VT instances${NC} or ${BOLD}All G and VT Spot Instance Requests${NC}"
    echo "  3. Click 'Request increase at account-level'"
    echo "  4. Enter new quota value: ${BOLD}64${NC}"
    echo "  5. Submit request"
    echo ""
    echo "  ${CYAN}Option 2: AWS CLI${NC}"
    echo "  ${GRAY}# For On-Demand${NC}"
    echo "  aws service-quotas request-service-quota-increase \\"
    echo "    --service-code ec2 \\"
    echo "    --quota-code L-DB2E81BA \\"
    echo "    --desired-value 64 \\"
    echo "    --region $region"
    echo ""
    echo "  ${GRAY}# For Spot${NC}"
    echo "  aws service-quotas request-service-quota-increase \\"
    echo "    --service-code ec2 \\"
    echo "    --quota-code L-3819A6DF \\"
    echo "    --desired-value 64 \\"
    echo "    --region $region"
    echo ""
    echo "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  ${YELLOW}⏱  Quota increase typically takes 24-48 hours${NC}"
    echo ""
}

# ==============================================================================
# Request Quota Increase (Interactive)
# ==============================================================================

request_quota_increase() {
    local quota_type="$1"  # "spot" or "ondemand"
    local desired_value="${2:-64}"
    local region="${3:-$REGION}"
    
    local quota_code
    local quota_name
    
    case "$quota_type" in
        spot)
            quota_code="L-3819A6DF"
            quota_name="All G and VT Spot Instance Requests"
            ;;
        ondemand)
            quota_code="L-DB2E81BA"
            quota_name="Running On-Demand G and VT instances"
            ;;
        *)
            log "ERROR" "Invalid quota type: $quota_type"
            return 1
            ;;
    esac
    
    log "INFO" "Requesting quota increase..."
    echo "  Quota: $quota_name"
    echo "  Region: $region"
    echo "  Desired Value: $desired_value vCPUs"
    echo ""
    
    local result
    result=$(aws service-quotas request-service-quota-increase \
        --service-code ec2 \
        --quota-code "$quota_code" \
        --desired-value "$desired_value" \
        --region "$region" \
        2>&1)
    
    if [[ $? -eq 0 ]]; then
        local case_id
        case_id=$(echo "$result" | grep -o 'RequestId": "[^"]*' | cut -d'"' -f3)
        
        log "SUCCESS" "Quota increase request submitted"
        echo "  Request ID: $case_id"
        echo "  Status: Pending approval (typically 24-48 hours)"
        echo ""
        return 0
    else
        log "ERROR" "Failed to request quota increase"
        echo "$result"
        return 1
    fi
}
