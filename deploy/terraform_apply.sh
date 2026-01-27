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

rollback_on_failure() {
    log "WARN" "Deployment failed - initiating automatic rollback..."
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ROLLBACK IN PROGRESS${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Cleaning up partially created resources to avoid orphaned infrastructure..."
    echo ""
    
    cd "$ENV_DIR"
    
    # Run terraform destroy to clean up any created resources
    if terraform destroy -input=false -auto-approve 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Terraform rollback completed"
        save_state "rolled_back"
    else
        log "ERROR" "Terraform rollback failed - some resources may remain"
        echo ""
        echo -e "${RED}WARNING: Automatic rollback failed!${NC}"
        echo "Please manually clean up resources using:"
        echo "  terraform destroy"
        echo "  Or check AWS Console for orphaned resources"
        save_state "rollback_failed"
    fi
    
    # Clean up orphaned IAM resources that Terraform may miss
    _cleanup_orphaned_iam_resources
    
    # Clean build artifacts
    rm -f tfplan 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ROLLBACK COMPLETE${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
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
# Terraform Apply
# ==============================================================================

terraform_apply() {
    log "STEP" "Deploying infrastructure..."
    
    cd "$ENV_DIR"
    
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
            echo "  - vCPU quota limits (most common for GPU instances)"
            echo "  - IAM permission issues"
            echo "  - Instance type availability in the region"
            echo ""
            
            if confirm "Do you want to rollback and clean up all created resources?" "Y"; then
                rollback_on_failure
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
        
        if confirm "Deployment failed. Do you want to rollback and clean up resources?" "Y"; then
            rollback_on_failure
        else
            log "WARN" "Skipping rollback - partial resources may remain"
            save_state "failed"
        fi
        
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
