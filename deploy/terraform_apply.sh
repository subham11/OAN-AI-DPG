#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Apply
# ==============================================================================
# Functions for applying Terraform plans and deploying infrastructure.
# Includes rollback on failure and deployment summary.
# ==============================================================================

# ==============================================================================
# Rollback on Failure
# ==============================================================================
# Uses the comprehensive cleanup script for safe resource deletion in the
# correct dependency order to avoid orphaned infrastructure.
#
# Deletion Order:
# 1. EC2 / ASG / ELB
# 2. NAT Gateway → Release EIP
# 3. VPC Endpoints
# 4. Peering / TGW / VPN
# 5. RDS / OpenSearch / ElastiCache
# 6. ECS / EKS / Lambda (VPC-enabled)
# 7. ENIs
# 8. Subnets
# 9. Route tables / SGs / NACLs
# 10. Internet Gateway
# 11. VPC
# 12. Orphaned resources (CloudWatch, IAM, EventBridge)
# ==============================================================================

rollback_on_failure() {
    local error_type="${1:-unknown}"
    local region="${REGION:-us-east-1}"
    local project_prefix="${PROJECT_NAME:-dpg-infra}"
    
    log "WARN" "Deployment failed - initiating automatic rollback..."
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    ROLLBACK IN PROGRESS                       ║${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}║  Failure Type: $(printf '%-44s' "$error_type")║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Cleaning up partially created resources in safe dependency order..."
    echo ""
    
    save_state "rolling_back"
    
    # Determine which cleanup method to use based on platform
    case "$PLATFORM" in
        aws)
            _rollback_aws_resources "$region" "$project_prefix"
            ;;
        azure)
            _rollback_azure_resources
            ;;
        gcp)
            _rollback_gcp_resources
            ;;
        *)
            _rollback_terraform_only
            ;;
    esac
    
    # Clean build artifacts
    rm -f "${ENV_DIR}/tfplan" 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                    ROLLBACK COMPLETE                          ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# AWS Rollback - Uses comprehensive cleanup script
# ==============================================================================

_rollback_aws_resources() {
    local region="$1"
    local project_prefix="$2"
    local cleanup_script="${SCRIPT_DIR}/cleanup.sh"
    
    # Check if cleanup script exists
    if [[ -f "$cleanup_script" ]]; then
        log "INFO" "Using comprehensive cleanup script for safe rollback..."
        echo ""
        
        # Build cleanup command with appropriate options
        local cleanup_cmd="$cleanup_script --region $region --prefix $project_prefix"
        
        # Add AWS profile if set
        if [[ -n "$AWS_PROFILE" ]]; then
            cleanup_cmd="$cleanup_cmd --profile $AWS_PROFILE"
        fi
        
        # Add environment
        cleanup_cmd="$cleanup_cmd --environment ${ENVIRONMENT:-staging}"
        
        # Force mode for automatic rollback (no prompts)
        cleanup_cmd="$cleanup_cmd --force"
        
        log "INFO" "Executing: $cleanup_cmd"
        echo ""
        
        if eval "$cleanup_cmd"; then
            log "SUCCESS" "Comprehensive cleanup completed successfully"
            save_state "rolled_back"
        else
            log "WARN" "Cleanup script encountered some issues"
            log "INFO" "Falling back to Terraform destroy..."
            _rollback_terraform_only
        fi
    else
        log "WARN" "Cleanup script not found at: $cleanup_script"
        log "INFO" "Falling back to Terraform destroy..."
        _rollback_terraform_only
    fi
}

# ==============================================================================
# Azure Rollback
# ==============================================================================

_rollback_azure_resources() {
    local resource_group="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}-rg"
    
    log "INFO" "Attempting to delete Azure resource group: $resource_group"
    
    # Try Azure CLI first for faster cleanup
    if command -v az &>/dev/null; then
        if az group exists --name "$resource_group" 2>/dev/null | grep -q "true"; then
            log "INFO" "Deleting resource group (this may take several minutes)..."
            if az group delete --name "$resource_group" --yes --no-wait 2>/dev/null; then
                log "SUCCESS" "Azure resource group deletion initiated"
                save_state "rolled_back"
                return 0
            fi
        fi
    fi
    
    # Fall back to Terraform destroy
    _rollback_terraform_only
}

# ==============================================================================
# GCP Rollback
# ==============================================================================

_rollback_gcp_resources() {
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    
    log "INFO" "Cleaning up GCP resources..."
    
    # Try Terraform destroy first as it handles dependencies better
    _rollback_terraform_only
    
    # Then clean up any orphaned service accounts
    if [[ -n "$project_id" ]]; then
        _cleanup_gcp_iam_resources "${PROJECT_NAME:-dpg-infra}"
    fi
}

# ==============================================================================
# Terraform-only Rollback (fallback)
# ==============================================================================

_rollback_terraform_only() {
    log "INFO" "Running Terraform destroy for rollback..."
    
    cd "$ENV_DIR"
    
    # Run terraform destroy to clean up any created resources
    if terraform destroy -input=false -auto-approve 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Terraform rollback completed"
        save_state "rolled_back"
    else
        log "ERROR" "Terraform rollback failed - some resources may remain"
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                    ROLLBACK FAILED                            ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║  Some resources could not be automatically cleaned up.        ║${NC}"
        echo -e "${RED}║                                                               ║${NC}"
        echo -e "${RED}║  Please run the cleanup script manually:                      ║${NC}"
        echo -e "${RED}║    ./deploy/cleanup.sh --region $REGION --force               ║${NC}"
        echo -e "${RED}║                                                               ║${NC}"
        echo -e "${RED}║  Or check the AWS Console for orphaned resources.             ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        save_state "rollback_failed"
    fi
    
    # Clean up orphaned IAM resources that Terraform may miss
    _cleanup_orphaned_iam_resources
}

# ==============================================================================
# Cleanup Orphaned IAM Resources
# ==============================================================================
# Terraform destroy may not clean up IAM resources if there are dependency
# issues or if the resources were created but the apply failed mid-way.
# This function ensures complete cleanup of project-related IAM resources.
# ==============================================================================

_cleanup_orphaned_iam_resources() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    
    log "INFO" "Checking for orphaned IAM resources with prefix: $project_prefix"
    
    case "$PLATFORM" in
        aws)
            _cleanup_aws_iam_resources "$project_prefix"
            ;;
        azure)
            # Azure uses managed identities which are cleaned up with resource groups
            log "INFO" "Azure managed identities are cleaned up with resource groups"
            ;;
        gcp)
            _cleanup_gcp_iam_resources "$project_prefix"
            ;;
    esac
}

_cleanup_aws_iam_resources() {
    local prefix="$1"
    local orphaned_found=false
    
    # Check and clean up instance profiles
    local instance_profiles
    instance_profiles=$(aws iam list-instance-profiles \
        --query "InstanceProfiles[?contains(InstanceProfileName, \`$prefix\`)].InstanceProfileName" \
        --output text 2>/dev/null || echo "")
    
    for profile in $instance_profiles; do
        orphaned_found=true
        log "INFO" "Cleaning up orphaned instance profile: $profile"
        
        # Get roles attached to the instance profile
        local roles
        roles=$(aws iam get-instance-profile --instance-profile-name "$profile" \
            --query 'InstanceProfile.Roles[*].RoleName' --output text 2>/dev/null || echo "")
        
        for role in $roles; do
            aws iam remove-role-from-instance-profile \
                --instance-profile-name "$profile" \
                --role-name "$role" 2>/dev/null || true
        done
        
        aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null && \
            log "SUCCESS" "Deleted instance profile: $profile" || \
            log "WARN" "Could not delete instance profile: $profile"
    done
    
    # Check and clean up IAM roles
    local roles
    roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, \`$prefix\`)].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role in $roles; do
        orphaned_found=true
        log "INFO" "Cleaning up orphaned IAM role: $role"
        
        # Detach all managed policies
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies --role-name "$role" \
            --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete all inline policies
        local inline_policies
        inline_policies=$(aws iam list-role-policies --role-name "$role" \
            --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        for policy_name in $inline_policies; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        aws iam delete-role --role-name "$role" 2>/dev/null && \
            log "SUCCESS" "Deleted IAM role: $role" || \
            log "WARN" "Could not delete IAM role: $role"
    done
    
    # Check and clean up custom IAM policies
    local policies
    policies=$(aws iam list-policies --scope Local \
        --query "Policies[?contains(PolicyName, \`$prefix\`)].[PolicyArn,PolicyName]" \
        --output text 2>/dev/null || echo "")
    
    while read -r policy_arn policy_name; do
        if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
            orphaned_found=true
            log "INFO" "Cleaning up orphaned IAM policy: $policy_name"
            
            # Delete all non-default policy versions first
            local versions
            versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
                --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
            
            for version in $versions; do
                aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" 2>/dev/null || true
            done
            
            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null && \
                log "SUCCESS" "Deleted IAM policy: $policy_name" || \
                log "WARN" "Could not delete IAM policy: $policy_name"
        fi
    done <<< "$policies"
    
    if [[ "$orphaned_found" == "true" ]]; then
        log "SUCCESS" "Orphaned IAM resources cleanup completed"
    else
        log "INFO" "No orphaned IAM resources found"
    fi
}

_cleanup_gcp_iam_resources() {
    local prefix="$1"
    
    # GCP service accounts cleanup
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -n "$project_id" ]]; then
        local service_accounts
        service_accounts=$(gcloud iam service-accounts list \
            --filter="displayName~$prefix OR email~$prefix" \
            --format="value(email)" 2>/dev/null || echo "")
        
        for sa in $service_accounts; do
            log "INFO" "Cleaning up orphaned service account: $sa"
            gcloud iam service-accounts delete "$sa" --quiet 2>/dev/null && \
                log "SUCCESS" "Deleted service account: $sa" || \
                log "WARN" "Could not delete service account: $sa"
        done
    fi
}

# ==============================================================================
# Check EC2/Compute Instance Creation
# ==============================================================================

verify_compute_instances() {
    log "INFO" "Verifying compute instances were created..."
    
    cd "$ENV_DIR"
    
    # Check for ASG or instance outputs
    local instance_count=0
    
    case "$PLATFORM" in
        aws)
            # Check for ASG instances
            instance_count=$(terraform output -json 2>/dev/null | jq -r '.asg_instances.value // 0' 2>/dev/null || echo "0")
            if [[ "$instance_count" == "null" ]] || [[ -z "$instance_count" ]]; then
                # Try checking ASG directly via AWS CLI
                local asg_name=$(terraform output -raw asg_name 2>/dev/null || echo "")
                if [[ -n "$asg_name" ]]; then
                    instance_count=$(aws autoscaling describe-auto-scaling-groups \
                        --auto-scaling-group-names "$asg_name" \
                        --query 'AutoScalingGroups[0].Instances | length(@)' \
                        --output text 2>/dev/null || echo "0")
                    
                    # If no instances, check for capacity issues
                    if [[ "$instance_count" == "0" || -z "$instance_count" ]]; then
                        check_asg_scaling_failures "$asg_name"
                    fi
                fi
            fi
            ;;
        azure)
            instance_count=$(terraform output -json 2>/dev/null | jq -r '.vmss_instance_count.value // 0' 2>/dev/null || echo "0")
            ;;
        gcp)
            instance_count=$(terraform output -json 2>/dev/null | jq -r '.mig_size.value // 0' 2>/dev/null || echo "0")
            ;;
    esac
    
    if [[ "$instance_count" -gt 0 ]]; then
        log "SUCCESS" "Compute instances verified: $instance_count running"
        return 0
    else
        log "WARN" "No compute instances detected - checking if creation failed..."
        return 1
    fi
}

# ==============================================================================
# Check ASG Scaling Failures (AWS-specific)
# ==============================================================================
# This function checks Auto Scaling Group scaling activities for failures,
# particularly Spot capacity issues, and provides helpful suggestions.
# ==============================================================================

check_asg_scaling_failures() {
    local asg_name="$1"
    local region="${REGION:-us-east-1}"
    
    log "INFO" "Checking Auto Scaling Group scaling activities..."
    
    # Get recent scaling activities
    local activities
    activities=$(aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "$asg_name" \
        --max-records 5 \
        --region "$region" \
        --query 'Activities[*].[StatusCode,StatusMessage,Cause]' \
        --output json 2>/dev/null)
    
    if [[ -z "$activities" || "$activities" == "[]" ]]; then
        return 0
    fi
    
    # Check for capacity-related failures
    local has_capacity_failure=false
    local failed_azs=()
    local suggested_azs=()
    
    # Parse activities for capacity failures
    while read -r status_code status_msg cause; do
        if [[ "$status_code" == "\"Failed\"" ]]; then
            # Check for spot capacity messages
            if echo "$status_msg" | grep -qi "insufficient.*capacity\|capacity.*unavailable"; then
                has_capacity_failure=true
                
                # Extract AZs mentioned in the message
                local az_pattern="$region[a-z]"
                local mentioned_azs=$(echo "$status_msg" | grep -oE "$az_pattern" | sort -u)
                
                for az in $mentioned_azs; do
                    if echo "$status_msg" | grep -q "do not have.*capacity.*$az\|$az.*insufficient"; then
                        failed_azs+=("$az")
                    elif echo "$status_msg" | grep -q "choosing $az\|available.*$az"; then
                        suggested_azs+=("$az")
                    fi
                done
            fi
        fi
    done < <(echo "$activities" | jq -r '.[] | "\(.[0]) \(.[1]) \(.[2])"')
    
    # If we detected capacity failures, show a helpful message
    if [[ "$has_capacity_failure" == "true" ]]; then
        echo ""
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}${BOLD}  ⚠ SPOT INSTANCE CAPACITY ISSUE DETECTED${NC}"
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Get instance type from terraform output
        local instance_type
        instance_type=$(terraform output -raw instance_type 2>/dev/null || echo "g5.4xlarge")
        
        # Remove duplicates from arrays
        failed_azs=($(printf '%s\n' "${failed_azs[@]}" | sort -u))
        suggested_azs=($(printf '%s\n' "${suggested_azs[@]}" | sort -u))
        
        # Remove failed AZs from suggested
        local clean_suggested=()
        for saz in "${suggested_azs[@]}"; do
            local is_failed=false
            for faz in "${failed_azs[@]}"; do
                if [[ "$saz" == "$faz" ]]; then
                    is_failed=true
                    break
                fi
            done
            if [[ "$is_failed" == "false" ]]; then
                clean_suggested+=("$saz")
            fi
        done
        suggested_azs=("${clean_suggested[@]}")
        
        if [[ ${#failed_azs[@]} -gt 0 ]]; then
            echo -e "  The ${BOLD}$instance_type${NC} Spot capacity is ${RED}not available${NC} in:"
            for az in "${failed_azs[@]}"; do
                echo -e "    ${RED}•${NC} $az"
            done
            echo ""
            echo -e "  The ASG is only configured to use those availability zones."
            echo ""
        fi
        
        if [[ ${#suggested_azs[@]} -gt 0 ]]; then
            echo -e "  ${GREEN}${BOLD}Capacity is available in:${NC}"
            for az in "${suggested_azs[@]}"; do
                echo -e "    ${GREEN}•${NC} $az"
            done
            echo ""
            
            # Suggest fix
            local new_az1="${suggested_azs[0]:-}"
            local new_az2="${suggested_azs[1]:-$new_az1}"
            
            echo -e "  ${BOLD}To fix this, update your terraform.tfvars:${NC}"
            echo -e "    ${CYAN}availability_zones = [\"$new_az1\", \"$new_az2\"]${NC}"
            echo ""
            echo -e "  Then run: ${CYAN}terraform apply${NC}"
        else
            # Query for AZs with spot capacity
            echo -e "  Checking for AZs with available capacity..."
            echo ""
            
            local available_azs
            available_azs=$(aws ec2 describe-spot-price-history \
                --region "$region" \
                --instance-types "$instance_type" \
                --product-descriptions "Linux/UNIX" \
                --start-time "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')" \
                --query 'SpotPriceHistory[*].AvailabilityZone' \
                --output text 2>/dev/null | tr '\t' '\n' | sort -u)
            
            if [[ -n "$available_azs" ]]; then
                echo -e "  ${GREEN}${BOLD}AZs with Spot capacity based on recent pricing:${NC}"
                for az in $available_azs; do
                    echo -e "    ${GREEN}•${NC} $az"
                done
                echo ""
                
                local first_two=$(echo "$available_azs" | head -2 | tr '\n' ' ')
                local az_arr=($first_two)
                
                echo -e "  ${BOLD}Suggested fix - update terraform.tfvars:${NC}"
                echo -e "    ${CYAN}availability_zones = [\"${az_arr[0]}\", \"${az_arr[1]:-${az_arr[0]}}\"]${NC}"
                echo ""
            fi
        fi
        
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

# ==============================================================================
# Terraform Apply
# ==============================================================================

terraform_apply() {
    log "STEP" "Deploying infrastructure..."
    
    cd "$ENV_DIR"
    
    # Run pre-flight checks to detect and fix resource conflicts
    if ! run_preflight_checks; then
        log "ERROR" "Pre-flight checks failed - cannot proceed with deployment"
        return 1
    fi
    
    # Check for existing resources and prompt user
    if ! check_existing_resources; then
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}This will create cloud resources that may incur costs.${NC}"
    
    if ! confirm "Do you want to proceed with the deployment?" "N"; then
        log "INFO" "Deployment cancelled by user"
        return 1
    fi
    
    echo ""
    log "INFO" "Starting deployment with progress tracking..."
    
    # Use progress bar version
    if terraform_apply_with_progress "tfplan" "$LOG_FILE"; then
        log "SUCCESS" "Terraform apply completed!"
        
        # Verify compute instances were created
        echo ""
        if ! verify_compute_instances; then
            echo ""
            echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}  EC2/COMPUTE INSTANCE CREATION FAILED${NC}"
            echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo "Infrastructure was created but compute instances failed to launch."
            echo "This is typically due to:"
            echo "  - Spot capacity unavailable in selected availability zones"
            echo "  - Instance type availability in the region"
            echo "  - Auto Scaling Group launch configuration issues"
            echo ""
            echo "Note: vCPU quota was already verified sufficient before deployment."
            echo ""
            
            if confirm "Do you want to rollback and clean up all created resources?" "Y"; then
                rollback_on_failure "EC2/Compute Instance Creation Failed"
                return 1
            else
                log "WARN" "Skipping rollback - resources will remain"
                save_state "partial_deploy"
                return 1
            fi
        fi
        
        save_state "deployed"
        return 0
    else
        log "ERROR" "Terraform apply failed"
        echo ""
        echo "Check the errors above or review: $LOG_FILE"
        echo ""
        
        # Check if zone failover was requested (capacity error handling)
        if [[ -f /tmp/zone_failover_requested.tmp ]] && [[ "$(cat /tmp/zone_failover_requested.tmp 2>/dev/null)" == "true" ]]; then
            local new_zone
            new_zone=$(cat /tmp/zone_failover_selection.tmp 2>/dev/null)
            rm -f /tmp/zone_failover_requested.tmp /tmp/zone_failover_selection.tmp
            
            if [[ -n "$new_zone" ]]; then
                echo ""
                log "INFO" "Zone failover requested to: $new_zone"
                
                if _retry_with_new_zone "$new_zone"; then
                    return 0
                else
                    log "ERROR" "Zone failover deployment also failed"
                    if confirm "Do you want to rollback and clean up resources?" "Y"; then
                        rollback_on_failure "Zone Failover Failed"
                    fi
                    return 1
                fi
            fi
        fi
        
        # Clean up temp files
        rm -f /tmp/zone_failover_requested.tmp /tmp/zone_failover_selection.tmp
        
        if confirm "Deployment failed. Do you want to rollback and clean up resources?" "Y"; then
            rollback_on_failure "Terraform Apply Failed"
        else
            log "WARN" "Skipping rollback - partial resources may remain"
            save_state "failed"
        fi
        
        return 1
    fi
}

# ==============================================================================
# Retry Deployment with New Zone
# ==============================================================================

_retry_with_new_zone() {
    local new_zone="$1"
    local region="${REGION:-us-east-1}"
    local tfvars_file="${ENV_DIR}/terraform.tfvars"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ZONE FAILOVER: Retrying with $new_zone${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Step 1: Update terraform.tfvars with new zone
    log "INFO" "Updating availability_zones in terraform.tfvars..."
    
    if [[ -f "$tfvars_file" ]]; then
        # Backup current tfvars
        cp "$tfvars_file" "${tfvars_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Update availability_zones
        if grep -q "^availability_zones" "$tfvars_file"; then
            # Replace existing
            sed -i.bak "s/^availability_zones.*=.*/availability_zones = [\"$new_zone\"]/" "$tfvars_file"
            rm -f "${tfvars_file}.bak"
        else
            # Add new
            echo "" >> "$tfvars_file"
            echo "# Updated by zone failover" >> "$tfvars_file"
            echo "availability_zones = [\"$new_zone\"]" >> "$tfvars_file"
        fi
        
        log "SUCCESS" "Updated availability_zones to: [\"$new_zone\"]"
    else
        log "ERROR" "Cannot find terraform.tfvars at: $tfvars_file"
        return 1
    fi
    
    # Step 2: Run preflight checks to see what can be reused
    echo ""
    log "INFO" "Running preflight checks for resource reuse..."
    echo ""
    
    if type run_preflight_checks &>/dev/null; then
        if ! run_preflight_checks; then
            log "WARN" "Preflight checks found issues - attempting to continue..."
        fi
    fi
    
    # Step 3: Re-run terraform plan
    echo ""
    log "INFO" "Creating new Terraform plan for zone: $new_zone..."
    
    cd "$ENV_DIR"
    
    if ! terraform plan -out=tfplan -input=false 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Terraform plan failed for new zone"
        return 1
    fi
    
    # Step 4: Show what will change
    echo ""
    log "INFO" "Reviewing changes for zone failover..."
    
    local resource_count
    resource_count=$(terraform show -json tfplan 2>/dev/null | grep -o '"resource_changes":\[[^]]*\]' | grep -o '"action"' | wc -l || echo "unknown")
    
    echo ""
    echo -e "  ${YELLOW}Zone failover will modify resources to use: $new_zone${NC}"
    echo ""
    
    if ! confirm "Proceed with zone failover deployment?" "Y"; then
        log "INFO" "Zone failover cancelled by user"
        return 1
    fi
    
    # Step 5: Apply the new plan
    echo ""
    log "INFO" "Applying zone failover deployment..."
    
    if terraform_apply_with_progress "tfplan" "$LOG_FILE"; then
        log "SUCCESS" "Zone failover deployment completed!"
        
        # Verify instances
        if verify_compute_instances; then
            save_state "deployed"
            echo ""
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  Zone Failover Successful!${NC}"
            echo -e "${GREEN}  Deployed to: $new_zone${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            return 0
        else
            log "ERROR" "Instances failed to launch in new zone"
            return 1
        fi
    else
        log "ERROR" "Zone failover apply failed"
        return 1
    fi
}

# ==============================================================================
# Deployment Summary Table
# ==============================================================================

show_deployment_summary() {
    log "STEP" "Deployment Summary"
    echo ""
    
    cd "$ENV_DIR"
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    DEPLOYMENT SUMMARY                          ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Get resource counts from terraform state
    local resources=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
    
    printf "${GREEN}%-40s %s${NC}\n" "Total Resources Created:" "$resources"
    echo ""
    
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  Resource Type                              │  Count/Status   │${NC}"
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────────┤${NC}"
    
    case "$PLATFORM" in
        aws)
            show_aws_resources
            ;;
        azure)
            show_azure_resources
            ;;
        gcp)
            show_gcp_resources
            ;;
    esac
    
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_aws_resources() {
    local vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    local alb_dns=$(terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
    local asg_name=$(terraform output -raw asg_name 2>/dev/null || echo "N/A")
    
    # Count resources by type
    local vpc_count=$(terraform state list 2>/dev/null | grep -c "aws_vpc" || echo "0")
    local subnet_count=$(terraform state list 2>/dev/null | grep -c "aws_subnet" || echo "0")
    local nat_count=$(terraform state list 2>/dev/null | grep -c "aws_nat_gateway" || echo "0")
    local sg_count=$(terraform state list 2>/dev/null | grep -c "aws_security_group" || echo "0")
    local alb_count=$(terraform state list 2>/dev/null | grep -c "aws_lb\." || echo "0")
    local asg_count=$(terraform state list 2>/dev/null | grep -c "aws_autoscaling_group" || echo "0")
    local lambda_count=$(terraform state list 2>/dev/null | grep -c "aws_lambda_function" || echo "0")
    local cw_alarm_count=$(terraform state list 2>/dev/null | grep -c "aws_cloudwatch_metric_alarm" || echo "0")
    local iam_role_count=$(terraform state list 2>/dev/null | grep -c "aws_iam_role\." || echo "0")
    
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "VPC" "$vpc_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Subnets (Public + Private)" "$subnet_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "NAT Gateways" "$nat_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Security Groups" "$sg_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Application Load Balancer" "$alb_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Auto Scaling Group" "$asg_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Lambda Functions (Scheduler)" "$lambda_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "CloudWatch Alarms" "$cw_alarm_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "IAM Roles" "$iam_role_count"
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│  %-44s│  %-15s│${NC}\n" "VPC ID" "$vpc_id"
    printf "${CYAN}│  %-44s│  %-15s│${NC}\n" "ALB DNS" "${alb_dns:0:15}..."
    printf "${CYAN}│  %-44s│  %-15s│${NC}\n" "ASG Name" "${asg_name:0:15}..."
}

show_azure_resources() {
    local rg_count=$(terraform state list 2>/dev/null | grep -c "azurerm_resource_group" || echo "0")
    local vnet_count=$(terraform state list 2>/dev/null | grep -c "azurerm_virtual_network" || echo "0")
    local subnet_count=$(terraform state list 2>/dev/null | grep -c "azurerm_subnet" || echo "0")
    local vmss_count=$(terraform state list 2>/dev/null | grep -c "azurerm_linux_virtual_machine_scale_set" || echo "0")
    local lb_count=$(terraform state list 2>/dev/null | grep -c "azurerm_lb\." || echo "0")
    local nsg_count=$(terraform state list 2>/dev/null | grep -c "azurerm_network_security_group" || echo "0")
    
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Resource Group" "$rg_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Virtual Network" "$vnet_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Subnets" "$subnet_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "VM Scale Set" "$vmss_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Load Balancer" "$lb_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Network Security Groups" "$nsg_count"
}

show_gcp_resources() {
    local vpc_count=$(terraform state list 2>/dev/null | grep -c "google_compute_network" || echo "0")
    local subnet_count=$(terraform state list 2>/dev/null | grep -c "google_compute_subnetwork" || echo "0")
    local mig_count=$(terraform state list 2>/dev/null | grep -c "google_compute_instance_group_manager" || echo "0")
    local lb_count=$(terraform state list 2>/dev/null | grep -c "google_compute_global_forwarding_rule" || echo "0")
    local firewall_count=$(terraform state list 2>/dev/null | grep -c "google_compute_firewall" || echo "0")
    local function_count=$(terraform state list 2>/dev/null | grep -c "google_cloudfunctions" || echo "0")
    
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "VPC Network" "$vpc_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Subnets" "$subnet_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Managed Instance Group" "$mig_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Load Balancer" "$lb_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Firewall Rules" "$firewall_count"
    printf "${WHITE}│  %-44s│  %-15s│${NC}\n" "Cloud Functions (Scheduler)" "$function_count"
}

# ==============================================================================
# Terraform Outputs
# ==============================================================================

show_outputs() {
    # First show deployment summary table
    show_deployment_summary
    
    # Show detailed resource table with ARNs
    show_resource_details
    
    log "STEP" "Connection Details"
    echo ""
    
    cd "$ENV_DIR"
    
    terraform output 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Check the outputs above for connection details"
    echo "  2. SSH to instances or access via load balancer URL"
    echo "  3. Run './deploy.sh --status' to check deployment status"
    echo "  4. Run './deploy.sh -p $PLATFORM -e $ENVIRONMENT --destroy' to tear down"
    echo ""
}

# ==============================================================================
# Detailed Resource Table with ARNs
# ==============================================================================

show_resource_details() {
    log "STEP" "Created Resources Details"
    echo ""
    
    cd "$ENV_DIR"
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                                    RESOURCE DETAILS                                                    ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    case "$PLATFORM" in
        aws)
            show_aws_resource_details
            ;;
        azure)
            show_azure_resource_details
            ;;
        gcp)
            show_gcp_resource_details
            ;;
    esac
}

show_aws_resource_details() {
    # Table header
    printf "${YELLOW}┌──────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${YELLOW}│  %-28s│  %-76s│${NC}\n" "Resource" "ID / ARN / Details"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # VPC
    local vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    local vpc_cidr=$(terraform output -raw vpc_cidr 2>/dev/null || echo "N/A")
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "VPC ID" "$vpc_id"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "VPC CIDR" "$vpc_cidr"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Subnets
    local public_subnets=$(terraform output -json public_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    local private_subnets=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r '.[]' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$public_subnets" && "$public_subnets" != "null" ]]; then
        printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Public Subnets" "${public_subnets:0:76}"
    fi
    if [[ -n "$private_subnets" && "$private_subnets" != "null" ]]; then
        printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Private Subnets" "${private_subnets:0:76}"
    fi
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Security Groups
    local alb_sg=$(terraform output -raw alb_security_group_id 2>/dev/null || echo "N/A")
    local instance_sg=$(terraform output -raw instance_security_group_id 2>/dev/null || echo "N/A")
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "ALB Security Group" "$alb_sg"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Instance Security Group" "$instance_sg"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Compute
    local launch_template=$(terraform output -raw launch_template_id 2>/dev/null || echo "N/A")
    local asg_name=$(terraform output -raw asg_name 2>/dev/null || echo "N/A")
    local asg_arn=$(terraform output -raw asg_arn 2>/dev/null || echo "N/A")
    local ami_id=$(terraform output -raw ami_id 2>/dev/null || echo "N/A")
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Launch Template" "$launch_template"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "ASG Name" "$asg_name"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "ASG ARN" "${asg_arn:0:76}"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "AMI ID" "$ami_id"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Load Balancer
    local alb_arn=$(terraform output -raw alb_arn 2>/dev/null || echo "N/A")
    local alb_dns=$(terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
    local target_group_arn=$(terraform output -raw target_group_arn 2>/dev/null || echo "N/A")
    if [[ "$alb_arn" != "N/A" && "$alb_arn" != "" && "$alb_arn" != "null" ]]; then
        printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "ALB ARN" "${alb_arn:0:76}"
        printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "ALB DNS Name" "${alb_dns:0:76}"
        printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Target Group ARN" "${target_group_arn:0:76}"
        printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    fi
    
    # Scheduler (Lambda + EventBridge)
    local scheduler_lambdas=$(terraform output -json scheduler_lambda_arns 2>/dev/null || echo "null")
    if [[ "$scheduler_lambdas" != "null" && "$scheduler_lambdas" != "" ]]; then
        local start_lambda=$(echo "$scheduler_lambdas" | jq -r '.start' 2>/dev/null || echo "")
        local stop_lambda=$(echo "$scheduler_lambdas" | jq -r '.stop' 2>/dev/null || echo "")
        if [[ -n "$start_lambda" && "$start_lambda" != "null" ]]; then
            printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Start Lambda ARN" "${start_lambda:0:76}"
        fi
        if [[ -n "$stop_lambda" && "$stop_lambda" != "null" ]]; then
            printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Stop Lambda ARN" "${stop_lambda:0:76}"
        fi
    fi
    
    local scheduler_rules=$(terraform output -json scheduler_eventbridge_rules 2>/dev/null || echo "null")
    if [[ "$scheduler_rules" != "null" && "$scheduler_rules" != "" ]]; then
        local start_rule=$(echo "$scheduler_rules" | jq -r '.start' 2>/dev/null || echo "")
        local stop_rule=$(echo "$scheduler_rules" | jq -r '.stop' 2>/dev/null || echo "")
        if [[ -n "$start_rule" && "$start_rule" != "null" ]]; then
            printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Start EventBridge Rule" "${start_rule:0:76}"
        fi
        if [[ -n "$stop_rule" && "$stop_rule" != "null" ]]; then
            printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Stop EventBridge Rule" "${stop_rule:0:76}"
        fi
    fi
    
    # IAM Resources from state
    local iam_roles=$(terraform state list 2>/dev/null | grep "aws_iam_role\." || true)
    local iam_profiles=$(terraform state list 2>/dev/null | grep "aws_iam_instance_profile\." || true)
    
    if [[ -n "$iam_roles" || -n "$iam_profiles" ]]; then
        printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
        for role in $iam_roles; do
            local role_arn=$(terraform state show "$role" 2>/dev/null | grep "arn" | head -1 | awk -F'"' '{print $2}')
            if [[ -n "$role_arn" ]]; then
                printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "IAM Role" "${role_arn:0:76}"
            fi
        done
        for profile in $iam_profiles; do
            local profile_arn=$(terraform state show "$profile" 2>/dev/null | grep "arn" | head -1 | awk -F'"' '{print $2}')
            if [[ -n "$profile_arn" ]]; then
                printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Instance Profile" "${profile_arn:0:76}"
            fi
        done
    fi
    
    printf "${YELLOW}└──────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘${NC}\n"
    echo ""
}

show_azure_resource_details() {
    printf "${YELLOW}┌──────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${YELLOW}│  %-28s│  %-76s│${NC}\n" "Resource" "ID / Details"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Get Azure outputs
    local rg_name=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")
    local vnet_id=$(terraform output -raw vnet_id 2>/dev/null || echo "N/A")
    local vmss_id=$(terraform output -raw vmss_id 2>/dev/null || echo "N/A")
    local lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")
    
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Resource Group" "$rg_name"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "VNet ID" "${vnet_id:0:76}"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "VM Scale Set ID" "${vmss_id:0:76}"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Load Balancer IP" "$lb_ip"
    
    printf "${YELLOW}└──────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘${NC}\n"
    echo ""
}

show_gcp_resource_details() {
    printf "${YELLOW}┌──────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${YELLOW}│  %-28s│  %-76s│${NC}\n" "Resource" "ID / Details"
    printf "${YELLOW}├──────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤${NC}\n"
    
    # Get GCP outputs
    local network_id=$(terraform output -raw network_id 2>/dev/null || echo "N/A")
    local mig_id=$(terraform output -raw mig_id 2>/dev/null || echo "N/A")
    local lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")
    
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Network ID" "${network_id:0:76}"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "MIG ID" "${mig_id:0:76}"
    printf "${WHITE}│  %-28s│  %-76s│${NC}\n" "Load Balancer IP" "$lb_ip"
    
    printf "${YELLOW}└──────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘${NC}\n"
    echo ""
}
