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
    local error_count=0
    
    # Use a temp file to capture terraform output for proper exit code handling
    # The pipe to while loop runs in a subshell, so PIPESTATUS doesn't work correctly
    local temp_output=$(mktemp)
    trap "rm -f '$temp_output'" EXIT
    
    # Run terraform apply, capture output to temp file while also processing it
    terraform apply -input=false -auto-approve "$plan_file" 2>&1 | tee "$temp_output" | while IFS= read -r line; do
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
        
        # Check for errors - display them immediately
        if [[ "$line" =~ ^╷$ ]] || [[ "$line" =~ ^│\ Error: ]]; then
            echo ""
            echo -e "${RED}$line${NC}"
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo ""
    
    # Check for errors in the terraform output (reliable method)
    # Look for "Error:" lines in the captured output
    if grep -q "^│ Error:" "$temp_output" 2>/dev/null || grep -q "Error: " "$temp_output" 2>/dev/null; then
        # Parse specific error types and display in user-friendly format
        _display_terraform_errors "$temp_output" "$duration"
        rm -f "$temp_output"
        return 1
    fi
    
    # Also check for "Apply complete!" to confirm success
    if grep -q "Apply complete!" "$temp_output" 2>/dev/null; then
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}✓ Deployment completed successfully in ${duration}s${NC}"
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        rm -f "$temp_output"
        return 0
    else
        # No "Apply complete!" and no errors - something unexpected happened
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${RED}✗ Deployment failed after ${duration}s (unexpected termination)${NC}"
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        rm -f "$temp_output"
        return 1
    fi
}

# ==============================================================================
# Display Terraform Errors in User-Friendly Format
# ==============================================================================

_display_terraform_errors() {
    local output_file="$1"
    local duration="$2"
    
    # First, extract the ACTUAL error message from Terraform output
    # Try multiple patterns since Terraform format varies
    local actual_error=""
    
    # Pattern 1: "Error: <message>" format
    actual_error=$(grep -E "^│?\s*Error:" "$output_file" 2>/dev/null | head -1 | sed 's/^│\s*//' | sed 's/Error:\s*//')
    
    # Pattern 2: Look for error in AWS/provider messages
    if [[ -z "$actual_error" ]]; then
        actual_error=$(grep -E "error|Error|ERROR" "$output_file" 2>/dev/null | grep -v "^#" | head -1)
    fi
    
    # Pattern 3: Extract from "│ Error:" block (common Terraform format)
    if [[ -z "$actual_error" ]]; then
        actual_error=$(sed -n '/Error:/,/│$/p' "$output_file" 2>/dev/null | head -3 | tr '\n' ' ')
    fi
    
    # Check for known error patterns and provide friendly names
    local error_type="Unknown Error"
    local error_detail=""
    
    if grep -q "AddressLimitExceeded" "$output_file" 2>/dev/null; then
        error_type="AddressLimitExceeded"
        error_detail="Maximum Elastic IPs reached in this region"
    elif grep -q "ResourceAlreadyExistsException" "$output_file" 2>/dev/null; then
        error_type="ResourceAlreadyExistsException"
        error_detail="CloudWatch Log Group already exists"
    elif grep -q "InvalidSubnet.Conflict" "$output_file" 2>/dev/null; then
        error_type="InvalidSubnet.Conflict"
        error_detail="Subnet CIDR block conflicts with existing subnet"
    elif grep -q "EntityAlreadyExists" "$output_file" 2>/dev/null; then
        error_type="EntityAlreadyExists"
        error_detail="IAM resource (Policy/Role) already exists"
    elif grep -q "VpcLimitExceeded" "$output_file" 2>/dev/null; then
        error_type="VpcLimitExceeded"
        error_detail="Maximum VPCs reached in this region"
    elif grep -q "InsufficientInstanceCapacity" "$output_file" 2>/dev/null; then
        error_type="InsufficientInstanceCapacity"
        error_detail="No Spot/On-Demand capacity available for instance type"
    elif grep -q "UnauthorizedOperation\|AccessDenied" "$output_file" 2>/dev/null; then
        error_type="AccessDenied"
        error_detail="IAM permission denied for this operation"
    elif grep -q "InvalidParameterValue" "$output_file" 2>/dev/null; then
        error_type="InvalidParameterValue"
        error_detail="Invalid parameter in resource configuration"
    elif grep -q "DependencyViolation" "$output_file" 2>/dev/null; then
        error_type="DependencyViolation"
        error_detail="Resource has dependencies that prevent modification"
    elif grep -q "InvalidGroup.NotFound\|InvalidSecurityGroupID" "$output_file" 2>/dev/null; then
        error_type="SecurityGroupError"
        error_detail="Security group not found or invalid"
    elif grep -q "InvalidVpcID\|InvalidSubnetID" "$output_file" 2>/dev/null; then
        error_type="NetworkError"
        error_detail="VPC or Subnet ID is invalid or not found"
    elif [[ -n "$actual_error" ]]; then
        # Use the extracted error as the type
        error_type="Terraform Error"
        error_detail="$actual_error"
    fi
    
    # Display the error in a clear format
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  DEPLOYMENT FAILED after ${duration}s                                           ║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║  Error Type: ${error_type}$(printf '%*s' $((55 - ${#error_type})) '')║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -n "$error_detail" ]]; then
        echo -e "  ${YELLOW}Cause:${NC} $error_detail"
        echo ""
    fi
    
    # Always show the raw Terraform error details
    echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}Terraform Error Details:${NC}"
    echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Extract and display error block - try multiple formats
    # Format 1: │ Error: style
    if grep -q "^│ Error:" "$output_file" 2>/dev/null; then
        grep -A5 "^│ Error:" "$output_file" 2>/dev/null | head -20 | while read -r errline; do
            echo -e "  ${RED}$errline${NC}"
        done
    # Format 2: Error: at start of line
    elif grep -q "^Error:" "$output_file" 2>/dev/null; then
        grep -A5 "^Error:" "$output_file" 2>/dev/null | head -20 | while read -r errline; do
            echo -e "  ${RED}$errline${NC}"
        done
    # Format 3: Any line containing Error
    else
        grep -i "error" "$output_file" 2>/dev/null | grep -v "^#" | head -10 | while read -r errline; do
            echo -e "  ${RED}$errline${NC}"
        done
    fi
    
    echo ""
    
    # Show which resource failed if we can find it
    local failed_resource
    failed_resource=$(grep -B5 "Error:" "$output_file" 2>/dev/null | grep -E "resource|module\." | tail -1)
    if [[ -n "$failed_resource" ]]; then
        echo -e "  ${YELLOW}Failed Resource:${NC} $failed_resource"
        echo ""
    fi
    
    # Check for capacity error and offer zone failover
    if grep -q "do not have sufficient.*capacity\|InsufficientInstanceCapacity" "$output_file" 2>/dev/null; then
        _handle_capacity_error "$output_file"
    fi
}

# ==============================================================================
# Handle Capacity Error - Offer Zone Failover
# ==============================================================================
# Detects availability zone capacity issues and offers alternative zones
# to the user, then reruns deployment with the new zone selection.
# ==============================================================================

# Global variable to store zone failover result
ZONE_FAILOVER_SELECTED=""
ZONE_FAILOVER_REQUESTED=false

_handle_capacity_error() {
    local output_file="$1"
    local error_text
    error_text=$(cat "$output_file" 2>/dev/null)
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  CAPACITY ERROR DETECTED - Zone Failover Available${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Extract the failed zone from error message
    local failed_zone=""
    failed_zone=$(echo "$error_text" | grep -oE "us-east-1[a-f]|us-west-2[a-f]|eu-west-1[a-f]|ap-south-1[a-f]|[a-z]+-[a-z]+-[0-9][a-f]" | head -1)
    
    # Extract suggested zones from the error message
    # Pattern: "choosing us-east-1b, us-east-1c, us-east-1d, us-east-1f"
    local suggested_zones=""
    suggested_zones=$(echo "$error_text" | grep -oE "choosing [a-z0-9, -]+" | sed 's/choosing //' | tr ',' '\n' | tr -d ' ' | grep -E "^[a-z]+-[a-z]+-[0-9][a-f]$")
    
    if [[ -z "$suggested_zones" ]]; then
        # Try alternate pattern extraction
        suggested_zones=$(echo "$error_text" | grep -oE "(us-east-1|us-west-2|eu-west-1|ap-south-1)[a-f]" | sort -u | grep -v "$failed_zone")
    fi
    
    if [[ -n "$failed_zone" ]]; then
        echo -e "  ${RED}Failed Zone:${NC} $failed_zone (no capacity for instance type)"
        echo ""
    fi
    
    if [[ -n "$suggested_zones" ]]; then
        echo -e "  ${GREEN}Available Zones with Capacity:${NC}"
        echo ""
        
        local zone_array=()
        local i=1
        while IFS= read -r zone; do
            if [[ -n "$zone" ]]; then
                zone_array+=("$zone")
                echo -e "    ${CYAN}$i)${NC} $zone"
                ((i++))
            fi
        done <<< "$suggested_zones"
        
        echo ""
        echo -e "    ${CYAN}$i)${NC} Cancel and rollback"
        echo ""
        
        # Interactive zone selection
        if [[ -t 0 ]]; then
            local selection
            read -p "Select a zone to retry deployment [1-$i]: " selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -lt "$i" ]]; then
                local selected_zone="${zone_array[$((selection-1))]}"
                echo ""
                echo -e "  ${GREEN}✓ Selected zone: $selected_zone${NC}"
                
                # Set global variable for zone failover
                ZONE_FAILOVER_SELECTED="$selected_zone"
                ZONE_FAILOVER_REQUESTED=true
                
                # Save to temp file for parent process to read
                echo "$selected_zone" > /tmp/zone_failover_selection.tmp
                echo "true" > /tmp/zone_failover_requested.tmp
                
                echo ""
                echo -e "  ${YELLOW}Zone failover will be attempted with: $selected_zone${NC}"
                echo ""
            else
                echo ""
                echo -e "  ${YELLOW}Zone failover cancelled. Proceeding with rollback...${NC}"
                echo "false" > /tmp/zone_failover_requested.tmp
            fi
        else
            echo "  (Non-interactive mode - zone failover requires user input)"
            echo ""
            echo "  To retry with a different zone, run deployment again with:"
            echo "    availability_zones = [\"<selected-zone>\"]"
            echo ""
        fi
    else
        # No suggested zones found, query AWS for available zones
        echo "  Querying available zones in the region..."
        _query_available_zones
    fi
}

# ==============================================================================
# Query Available Zones from AWS
# ==============================================================================

_query_available_zones() {
    local region="${REGION:-us-east-1}"
    
    local zones
    zones=$(aws ec2 describe-availability-zones --region "$region" \
        --query "AvailabilityZones[?State=='available'].ZoneName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$zones" ]]; then
        echo ""
        echo -e "  ${GREEN}Available Zones in $region:${NC}"
        echo ""
        
        local zone_array=()
        local i=1
        for zone in $zones; do
            zone_array+=("$zone")
            echo -e "    ${CYAN}$i)${NC} $zone"
            ((i++))
        done
        
        echo ""
        echo -e "    ${CYAN}$i)${NC} Cancel and rollback"
        echo ""
        
        if [[ -t 0 ]]; then
            local selection
            read -p "Select a zone to retry deployment [1-$i]: " selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -lt "$i" ]]; then
                local selected_zone="${zone_array[$((selection-1))]}"
                echo ""
                echo -e "  ${GREEN}✓ Selected zone: $selected_zone${NC}"
                
                ZONE_FAILOVER_SELECTED="$selected_zone"
                ZONE_FAILOVER_REQUESTED=true
                
                echo "$selected_zone" > /tmp/zone_failover_selection.tmp
                echo "true" > /tmp/zone_failover_requested.tmp
                
                echo ""
                echo -e "  ${YELLOW}Zone failover will be attempted with: $selected_zone${NC}"
                echo ""
            else
                echo ""
                echo -e "  ${YELLOW}Zone failover cancelled.${NC}"
                echo "false" > /tmp/zone_failover_requested.tmp
            fi
        fi
    else
        echo "  Could not query available zones. Please check AWS credentials."
    fi
}
