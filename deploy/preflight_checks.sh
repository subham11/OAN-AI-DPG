#!/bin/bash
# ==============================================================================
# DPG Deployment - Pre-flight Checks
# ==============================================================================
# Checks for common AWS resource conflicts and limits BEFORE Terraform apply.
# Attempts auto-remediation where possible, provides clear error messages when not.
# ==============================================================================

# Source logging utilities if not already loaded
if ! type log &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/utils_logging.sh"
fi

# ==============================================================================
# Error Display Function
# ==============================================================================

show_preflight_error() {
    local error_type="$1"
    local error_message="$2"
    local additional_info="${3:-}"
    
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  DEPLOYMENT BLOCKED: ${error_type}${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}Error:${NC} $error_message"
    if [[ -n "$additional_info" ]]; then
        echo ""
        echo -e "  ${YELLOW}Details:${NC}"
        echo "$additional_info" | sed 's/^/    /'
    fi
    echo ""
}

show_preflight_fix_success() {
    local issue_type="$1"
    local fix_description="$2"
    
    echo -e "  ${GREEN}✓${NC} Fixed: $issue_type"
    echo -e "    $fix_description"
}

show_preflight_fix_attempt() {
    local issue_type="$1"
    echo -e "  ${YELLOW}⚠${NC} Found: $issue_type"
    echo -e "    Attempting auto-fix..."
}

# ==============================================================================
# Check 1: Elastic IP Limits (AddressLimitExceeded)
# ==============================================================================

check_elastic_ip_limits() {
    local region="${REGION:-us-east-1}"
    local required_eips="${1:-2}"  # NAT gateways typically need 2 EIPs
    
    log "INFO" "Checking Elastic IP limits..." >&2
    
    # Get current EIP count
    local current_eips
    current_eips=$(aws ec2 describe-addresses --region "$region" \
        --query "length(Addresses)" --output text 2>/dev/null || echo "0")
    
    # Get EIP limit (default is 5)
    local eip_limit
    eip_limit=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-0263D0A3 \
        --region "$region" \
        --query "Quota.Value" --output text 2>/dev/null || echo "5")
    
    # Convert to integer
    eip_limit=${eip_limit%.*}
    
    local available_eips=$((eip_limit - current_eips))
    
    if [[ "$available_eips" -lt "$required_eips" ]]; then
        # Check for unassociated EIPs that could be released
        local unassociated_eips
        unassociated_eips=$(aws ec2 describe-addresses --region "$region" \
            --query "Addresses[?AssociationId==null].AllocationId" --output text 2>/dev/null || echo "")
        
        if [[ -n "$unassociated_eips" ]]; then
            show_preflight_fix_attempt "AddressLimitExceeded - Unassociated Elastic IPs found"
            
            local freed=0
            for alloc_id in $unassociated_eips; do
                if aws ec2 release-address --allocation-id "$alloc_id" --region "$region" 2>/dev/null; then
                    ((freed++))
                    log "INFO" "Released unassociated EIP: $alloc_id" >&2
                fi
                
                # Check if we have enough now
                if [[ "$((available_eips + freed))" -ge "$required_eips" ]]; then
                    break
                fi
            done
            
            if [[ "$((available_eips + freed))" -ge "$required_eips" ]]; then
                show_preflight_fix_success "AddressLimitExceeded" "Released $freed unassociated Elastic IP(s)"
                return 0
            fi
        fi
        
        # Could not fix - show error
        show_preflight_error \
            "AddressLimitExceeded - Maximum Elastic IPs reached" \
            "Cannot allocate $required_eips Elastic IP(s). Limit: $eip_limit, In use: $current_eips, Available: $available_eips" \
            "To fix this issue:
  1. Release unused Elastic IPs in AWS Console (EC2 > Elastic IPs)
  2. Or request a limit increase via AWS Service Quotas
  3. Current unassociated EIPs that could be released: $(echo "$unassociated_eips" | wc -w | tr -d ' ')"
        return 1
    fi
    
    log "INFO" "Elastic IP check passed ($available_eips available, $required_eips needed)" >&2
    return 0
}

# ==============================================================================
# Check 2: CloudWatch Log Groups (ResourceAlreadyExistsException)
# ==============================================================================

check_cloudwatch_log_groups() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    local region="${REGION:-us-east-1}"
    
    log "INFO" "Checking for existing CloudWatch Log Groups..." >&2
    
    # Log groups that our Terraform creates
    local log_groups=(
        "/aws/vpc/${project_prefix}-flow-logs"
        "/aws/lambda/${project_prefix}-start-instances"
        "/aws/lambda/${project_prefix}-stop-instances"
    )
    
    local existing_groups=()
    local failed_to_delete=()
    
    for lg in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$lg" --region "$region" \
            --query "logGroups[?logGroupName=='$lg'].logGroupName" --output text 2>/dev/null | grep -q "$lg"; then
            existing_groups+=("$lg")
        fi
    done
    
    if [[ ${#existing_groups[@]} -gt 0 ]]; then
        show_preflight_fix_attempt "ResourceAlreadyExistsException - CloudWatch Log Groups already exist"
        
        for lg in "${existing_groups[@]}"; do
            if aws logs delete-log-group --log-group-name "$lg" --region "$region" 2>/dev/null; then
                log "INFO" "Deleted CloudWatch Log Group: $lg" >&2
            else
                failed_to_delete+=("$lg")
            fi
        done
        
        if [[ ${#failed_to_delete[@]} -eq 0 ]]; then
            show_preflight_fix_success "ResourceAlreadyExistsException" "Deleted ${#existing_groups[@]} orphaned CloudWatch Log Group(s)"
            return 0
        else
            show_preflight_error \
                "ResourceAlreadyExistsException - CloudWatch Log Groups already exist" \
                "Cannot delete existing CloudWatch Log Groups" \
                "Failed to delete:
$(printf '  - %s\n' "${failed_to_delete[@]}")

To fix manually:
  aws logs delete-log-group --log-group-name \"<log-group-name>\" --region $region"
            return 1
        fi
    fi
    
    log "INFO" "CloudWatch Log Groups check passed (no conflicts)" >&2
    return 0
}

# ==============================================================================
# Check 3: IAM Policy Conflicts (EntityAlreadyExists)
# ==============================================================================
# Handles IAM policy conflicts with two options:
# Option A (best): Import the policy into Terraform state
# Option B: Make policy names unique by adding region suffix
# ==============================================================================

check_iam_policies() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    local region="${REGION:-us-east-1}"
    local env_dir="${ENV_DIR:-./environments/aws/staging}"
    
    log "INFO" "Checking for existing IAM policies..." >&2
    
    # Policies that our Terraform creates
    local policy_names=(
        "${project_prefix}-scheduler-logs-policy"
        "${project_prefix}-scheduler-ec2-policy"
        "${project_prefix}-scheduler-lambda-role"
    )
    
    local existing_policies=()
    local account_id
    account_id=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "")
    
    if [[ -z "$account_id" ]]; then
        log "WARN" "Could not get AWS account ID - skipping IAM policy check" >&2
        return 0
    fi
    
    for policy_name in "${policy_names[@]}"; do
        local policy_arn
        policy_arn=$(aws iam list-policies --scope Local \
            --query "Policies[?PolicyName=='$policy_name'].Arn" --output text 2>/dev/null || echo "")
        
        if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
            existing_policies+=("$policy_arn|$policy_name")
        fi
    done
    
    if [[ ${#existing_policies[@]} -gt 0 ]]; then
        show_preflight_fix_attempt "EntityAlreadyExists - IAM Policies already exist"
        
        echo "" >&2
        echo "Found ${#existing_policies[@]} existing IAM policy(ies):" >&2
        for entry in "${existing_policies[@]}"; do
            local policy_arn="${entry%|*}"
            local policy_name="${entry#*|}"
            echo "  - $policy_name" >&2
            echo "    ARN: $policy_arn" >&2
        done
        echo "" >&2
        
        # Try Option A: Import policies into Terraform state
        if _try_import_iam_policies "${existing_policies[@]}"; then
            return 0
        fi
        
        # Try Option B: Make policy names unique with region suffix
        if _try_unique_policy_names "${existing_policies[@]}"; then
            return 0
        fi
        
        # Both options failed - show comprehensive error
        _show_iam_policy_error "${existing_policies[@]}"
        return 1
    fi
    
    log "INFO" "IAM Policy check passed (no conflicts)" >&2
    return 0
}

# ==============================================================================
# Option A: Import existing policies into Terraform state
# ==============================================================================

_try_import_iam_policies() {
    local policies=("$@")
    local env_dir="${ENV_DIR:-./environments/aws/staging}"
    local import_success=true
    local imported_count=0
    local import_errors=()
    
    log "INFO" "Option A: Attempting to import existing policies into Terraform state..." >&2
    
    # Check if we're in a valid Terraform directory
    if [[ ! -f "${env_dir}/main.tf" ]]; then
        log "WARN" "Cannot find Terraform configuration at ${env_dir}" >&2
        log "INFO" "Skipping import, will try Option B..." >&2
        return 1
    fi
    
    cd "$env_dir" || return 1
    
    # Ensure Terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        log "INFO" "Initializing Terraform for import..." >&2
        if ! terraform init -backend=false >/dev/null 2>&1; then
            log "WARN" "Terraform init failed, skipping import" >&2
            return 1
        fi
    fi
    
    for entry in "${policies[@]}"; do
        local policy_arn="${entry%|*}"
        local policy_name="${entry#*|}"
        
        # Determine the Terraform resource address based on policy name
        local resource_address=""
        if [[ "$policy_name" == *"scheduler-logs-policy"* ]]; then
            resource_address="module.gpu_infrastructure.aws_iam_policy.scheduler_logs[0]"
        elif [[ "$policy_name" == *"scheduler-ec2-policy"* ]]; then
            resource_address="module.gpu_infrastructure.aws_iam_policy.scheduler_ec2[0]"
        else
            log "WARN" "Unknown policy type: $policy_name - skipping" >&2
            continue
        fi
        
        log "INFO" "Importing: $policy_name" >&2
        log "INFO" "  Resource: $resource_address" >&2
        log "INFO" "  ARN: $policy_arn" >&2
        
        # Check if resource is already in state
        if terraform state show "$resource_address" >/dev/null 2>&1; then
            log "INFO" "  Already in state - skipping" >&2
            ((imported_count++))
            continue
        fi
        
        # Attempt import
        local import_output
        if import_output=$(terraform import "$resource_address" "$policy_arn" 2>&1); then
            log "SUCCESS" "  Imported successfully" >&2
            ((imported_count++))
        else
            import_success=false
            import_errors+=("$policy_name: $import_output")
            log "WARN" "  Import failed: $import_output" >&2
        fi
    done
    
    if [[ "$import_success" == "true" ]] && [[ $imported_count -gt 0 ]]; then
        show_preflight_fix_success "EntityAlreadyExists" "Imported $imported_count IAM Policy(ies) into Terraform state"
        echo "" >&2
        echo -e "${GREEN}Option A succeeded!${NC}" >&2
        echo "Terraform now 'owns' these policies and will manage them." >&2
        echo "" >&2
        return 0
    fi
    
    if [[ ${#import_errors[@]} -gt 0 ]]; then
        log "WARN" "Option A (Import) failed with errors:" >&2
        for err in "${import_errors[@]}"; do
            echo "  - $err" >&2
        done
    fi
    
    return 1
}

# ==============================================================================
# Option B: Make policy names unique by adding region suffix
# ==============================================================================

_try_unique_policy_names() {
    local policies=("$@")
    local region="${REGION:-us-east-1}"
    local tfvars_file="${ENV_DIR:-./environments/aws/staging}/terraform.tfvars"
    
    log "INFO" "Option B: Checking if unique policy names can be used..." >&2
    
    # Check if the Terraform module supports a region suffix variable
    local module_vars_file="${PROJECT_ROOT:-$(pwd)}/modules/aws/variables.tf"
    
    if [[ ! -f "$module_vars_file" ]]; then
        log "WARN" "Cannot find module variables file" >&2
        return 1
    fi
    
    # Check if name_prefix already includes region
    local current_prefix
    if [[ -f "$tfvars_file" ]]; then
        current_prefix=$(grep -E "^name_prefix\s*=" "$tfvars_file" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' || echo "")
    fi
    
    if [[ "$current_prefix" == *"$region"* ]]; then
        log "INFO" "name_prefix already includes region: $current_prefix" >&2
        log "WARN" "Policy names should be unique but still conflict - deletion required" >&2
        return 1
    fi
    
    # Check if we can delete the policies (less destructive than modifying tfvars)
    log "INFO" "Attempting to delete conflicting policies to avoid name changes..." >&2
    
    local deleted_count=0
    local failed_to_delete=()
    
    for entry in "${policies[@]}"; do
        local policy_arn="${entry%|*}"
        local policy_name="${entry#*|}"
        
        # First, detach from all entities
        local attached_roles
        attached_roles=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" \
            --query "PolicyRoles[*].RoleName" --output text 2>/dev/null || echo "")
        
        for role in $attached_roles; do
            log "INFO" "  Detaching from role: $role" >&2
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Detach from users
        local attached_users
        attached_users=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" \
            --query "PolicyUsers[*].UserName" --output text 2>/dev/null || echo "")
        
        for user in $attached_users; do
            log "INFO" "  Detaching from user: $user" >&2
            aws iam detach-user-policy --user-name "$user" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Detach from groups
        local attached_groups
        attached_groups=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" \
            --query "PolicyGroups[*].GroupName" --output text 2>/dev/null || echo "")
        
        for group in $attached_groups; do
            log "INFO" "  Detaching from group: $group" >&2
            aws iam detach-group-policy --group-name "$group" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete all non-default versions
        local versions
        versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
            --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text 2>/dev/null || echo "")
        
        for version in $versions; do
            aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" 2>/dev/null || true
        done
        
        # Now delete the policy
        if aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null; then
            log "SUCCESS" "  Deleted IAM Policy: $policy_name" >&2
            ((deleted_count++))
        else
            failed_to_delete+=("$policy_name")
        fi
    done
    
    if [[ ${#failed_to_delete[@]} -eq 0 ]] && [[ $deleted_count -gt 0 ]]; then
        show_preflight_fix_success "EntityAlreadyExists" "Deleted $deleted_count orphaned IAM Policy(ies)"
        return 0
    fi
    
    # If deletion failed, suggest updating name_prefix to include region
    if [[ ${#failed_to_delete[@]} -gt 0 ]]; then
        log "WARN" "Could not delete policies. Suggesting unique naming..." >&2
        
        local new_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}-${region}"
        
        echo "" >&2
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo -e "${YELLOW}  OPTION B: Update name_prefix to include region${NC}" >&2
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo "" >&2
        echo "To make policy names unique, update terraform.tfvars:" >&2
        echo "" >&2
        echo "  Current:  name_prefix = \"${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}\"" >&2
        echo "  Change to: name_prefix = \"$new_prefix\"" >&2
        echo "" >&2
        echo "This will create policies like:" >&2
        echo "  $new_prefix-scheduler-logs-policy" >&2
        echo "  $new_prefix-scheduler-ec2-policy" >&2
        echo "" >&2
        
        # Ask user if they want to auto-update
        if [[ -t 0 ]]; then  # Check if running interactively
            read -p "Do you want to update name_prefix automatically? (yes/no): " auto_update
            if [[ "$auto_update" == "yes" ]]; then
                if _update_name_prefix_with_region "$new_prefix"; then
                    show_preflight_fix_success "EntityAlreadyExists" "Updated name_prefix to include region: $new_prefix"
                    return 0
                fi
            fi
        fi
    fi
    
    return 1
}

# ==============================================================================
# Update name_prefix in terraform.tfvars
# ==============================================================================

_update_name_prefix_with_region() {
    local new_prefix="$1"
    local tfvars_file="${ENV_DIR:-./environments/aws/staging}/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log "ERROR" "terraform.tfvars not found at: $tfvars_file" >&2
        return 1
    fi
    
    # Backup the file
    cp "$tfvars_file" "${tfvars_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if name_prefix exists
    if grep -q "^name_prefix" "$tfvars_file"; then
        # Update existing
        sed -i.bak "s/^name_prefix.*=.*/name_prefix = \"$new_prefix\"/" "$tfvars_file"
    else
        # Add new
        echo "" >> "$tfvars_file"
        echo "# Updated by preflight check to avoid IAM policy conflicts" >> "$tfvars_file"
        echo "name_prefix = \"$new_prefix\"" >> "$tfvars_file"
    fi
    
    rm -f "${tfvars_file}.bak"
    
    log "SUCCESS" "Updated name_prefix in terraform.tfvars" >&2
    return 0
}

# ==============================================================================
# Show comprehensive IAM policy error when both options fail
# ==============================================================================

_show_iam_policy_error() {
    local policies=("$@")
    local region="${REGION:-us-east-1}"
    local account_id
    account_id=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "ACCOUNT_ID")
    
    echo "" >&2
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${RED}║  ERROR: EntityAlreadyExists - IAM Policies Already Exist                  ║${NC}" >&2
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════════╣${NC}" >&2
    echo -e "${RED}║  Both automatic resolution options failed.                                ║${NC}" >&2
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${YELLOW}  MANUAL FIX - Option A (Recommended): Import into Terraform${NC}" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo "If these policies are expected to exist, import them:" >&2
    echo "" >&2
    
    for entry in "${policies[@]}"; do
        local policy_arn="${entry%|*}"
        local policy_name="${entry#*|}"
        
        local resource_addr="aws_iam_policy.RESOURCE_NAME[0]"
        if [[ "$policy_name" == *"scheduler-logs"* ]]; then
            resource_addr="module.gpu_infrastructure.aws_iam_policy.scheduler_logs[0]"
        elif [[ "$policy_name" == *"scheduler-ec2"* ]]; then
            resource_addr="module.gpu_infrastructure.aws_iam_policy.scheduler_ec2[0]"
        fi
        
        echo -e "  ${CYAN}terraform import \\${NC}" >&2
        echo -e "  ${CYAN}  $resource_addr \\${NC}" >&2
        echo -e "  ${CYAN}  $policy_arn${NC}" >&2
        echo "" >&2
    done
    
    echo "Terraform will then 'own' these policies and stop fighting AWS." >&2
    echo "" >&2
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${YELLOW}  MANUAL FIX - Option B: Make Policy Names Unique${NC}" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo "Update terraform.tfvars to include region in name_prefix:" >&2
    echo "" >&2
    echo "  Current (risky across retries):" >&2
    echo "    name_prefix = \"${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}\"" >&2
    echo "" >&2
    echo "  Better (includes region):" >&2
    echo "    name_prefix = \"${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}-${region}\"" >&2
    echo "" >&2
    echo "  Best (includes random suffix for guaranteed uniqueness):" >&2
    echo "    # In Terraform: \${var.name_prefix}-\${random_id.suffix.hex}" >&2
    echo "" >&2
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${YELLOW}  MANUAL FIX - Option C: Delete Policies Manually${NC}" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo "1. Go to AWS Console > IAM > Policies" >&2
    echo "2. Search for '${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}'" >&2
    echo "3. For each policy:" >&2
    echo "   a. Click 'Policy usage' to see attached entities" >&2
    echo "   b. Detach from all roles/users/groups" >&2
    echo "   c. Delete the policy" >&2
    echo "" >&2
    echo "Or use AWS CLI:" >&2
    
    for entry in "${policies[@]}"; do
        local policy_arn="${entry%|*}"
        echo "" >&2
        echo -e "  ${CYAN}# Delete policy: ${entry#*|}${NC}" >&2
        echo -e "  ${CYAN}aws iam delete-policy --policy-arn $policy_arn${NC}" >&2
    done
    echo "" >&2
}

# ==============================================================================
# Check 4: VPC Limits (VpcLimitExceeded)
# ==============================================================================

check_vpc_limits() {
    local region="${REGION:-us-east-1}"
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    
    log "INFO" "Checking VPC limits..." >&2
    
    # Get current VPC count
    local current_vpcs
    current_vpcs=$(aws ec2 describe-vpcs --region "$region" \
        --query "length(Vpcs)" --output text 2>/dev/null || echo "0")
    
    # Get VPC limit
    local vpc_limit
    vpc_limit=$(aws service-quotas get-service-quota \
        --service-code vpc \
        --quota-code L-F678F1CE \
        --region "$region" \
        --query "Quota.Value" --output text 2>/dev/null || echo "5")
    
    # Convert to integer
    vpc_limit=${vpc_limit%.*}
    
    if [[ "$current_vpcs" -ge "$vpc_limit" ]]; then
        # Check for orphaned project VPCs we can clean up
        local orphaned_vpcs
        orphaned_vpcs=$(aws ec2 describe-vpcs --region "$region" \
            --filters "Name=tag:Name,Values=*${project_prefix}*" \
            --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]]" --output text 2>/dev/null || echo "")
        
        if [[ -n "$orphaned_vpcs" ]]; then
            show_preflight_fix_attempt "VpcLimitExceeded - Orphaned project VPCs found"
            
            local deleted=0
            while read -r vpc_id vpc_name; do
                if [[ -n "$vpc_id" ]]; then
                    if _delete_vpc_and_dependencies "$vpc_id" "$region"; then
                        ((deleted++))
                        log "INFO" "Deleted orphaned VPC: $vpc_id ($vpc_name)" >&2
                    fi
                fi
            done <<< "$orphaned_vpcs"
            
            if [[ "$deleted" -gt 0 ]]; then
                show_preflight_fix_success "VpcLimitExceeded" "Deleted $deleted orphaned VPC(s)"
                return 0
            fi
        fi
        
        # List all VPCs for user to review
        local vpc_list
        vpc_list=$(aws ec2 describe-vpcs --region "$region" \
            --query "Vpcs[*].[VpcId,CidrBlock,Tags[?Key=='Name'].Value|[0]]" --output table 2>/dev/null || echo "Unable to list VPCs")
        
        show_preflight_error \
            "VpcLimitExceeded - Maximum VPCs reached" \
            "Cannot create new VPC. Limit: $vpc_limit, Current: $current_vpcs" \
            "Current VPCs in $region:
$vpc_list

To fix this issue:
  1. Delete unused VPCs in AWS Console (VPC > Your VPCs)
  2. Or request a limit increase via AWS Service Quotas
  3. Quota code: L-F678F1CE"
        return 1
    fi
    
    log "INFO" "VPC limit check passed ($current_vpcs of $vpc_limit used)" >&2
    return 0
}

# Helper function to delete VPC and its dependencies
_delete_vpc_and_dependencies() {
    local vpc_id="$1"
    local region="$2"
    
    # Delete in order: IGW, Subnets, Route Tables, Security Groups, NAT Gateways, then VPC
    
    # Detach and delete Internet Gateway
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways --region "$region" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$region" 2>/dev/null || true
    fi
    
    # Delete NAT Gateways
    local nat_gws
    nat_gws=$(aws ec2 describe-nat-gateways --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
        --query "NatGateways[*].NatGatewayId" --output text 2>/dev/null || echo "")
    
    for nat_id in $nat_gws; do
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$region" 2>/dev/null || true
    done
    
    # Wait for NAT gateways to delete (with timeout)
    if [[ -n "$nat_gws" ]]; then
        sleep 5
    fi
    
    # Delete Subnets
    local subnets
    subnets=$(aws ec2 describe-subnets --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "Subnets[*].SubnetId" --output text 2>/dev/null || echo "")
    
    for subnet_id in $subnets; do
        aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" 2>/dev/null || true
    done
    
    # Delete Route Tables (except main)
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text 2>/dev/null || echo "")
    
    for rt_id in $route_tables; do
        # Disassociate first
        local assoc_ids
        assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --region "$region" \
            --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text 2>/dev/null || echo "")
        
        for assoc_id in $assoc_ids; do
            aws ec2 disassociate-route-table --association-id "$assoc_id" --region "$region" 2>/dev/null || true
        done
        
        aws ec2 delete-route-table --route-table-id "$rt_id" --region "$region" 2>/dev/null || true
    done
    
    # Delete Security Groups (except default)
    local sgs
    sgs=$(aws ec2 describe-security-groups --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || echo "")
    
    for sg_id in $sgs; do
        aws ec2 delete-security-group --group-id "$sg_id" --region "$region" 2>/dev/null || true
    done
    
    # Finally, delete VPC
    if aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$region" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Check 5: Subnet CIDR Conflicts (InvalidSubnet.Conflict)
# ==============================================================================
# Handles subnet conflicts with two options:
# Option 1: Reuse existing subnets if they match our required CIDRs
# Option 2: Find alternative unused CIDRs if reuse is not possible
# ==============================================================================

# Global variable to store subnet reuse/alternative configuration
# Note: Using simple assignment instead of 'declare -g' for Bash 3.x compatibility (macOS default)
SUBNET_REUSE_CONFIG=""
SUBNET_ALTERNATIVE_CIDRS=""

check_subnet_conflicts() {
    local region="${REGION:-us-east-1}"
    local vpc_cidr="${VPC_CIDR:-10.0.0.0/16}"
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    
    log "INFO" "Checking for subnet CIDR conflicts..." >&2
    
    # Our Terraform uses these CIDRs (based on modules/aws/subnets.tf)
    # Format: cidr:type (public or private)
    local our_cidrs=(
        "10.0.1.0/24:public"    # public subnet 1
        "10.0.2.0/24:public"    # public subnet 2
        "10.0.11.0/24:private"  # private subnet 1
        "10.0.12.0/24:private"  # private subnet 2
    )
    
    local conflicts=()
    local reusable_subnets=()
    local needs_alternative=()
    
    for cidr_entry in "${our_cidrs[@]}"; do
        local cidr="${cidr_entry%:*}"
        local subnet_type="${cidr_entry#*:}"
        
        # Check if this CIDR exists in any VPC
        local existing
        existing=$(aws ec2 describe-subnets --region "$region" \
            --filters "Name=cidr-block,Values=$cidr" \
            --query "Subnets[0].[SubnetId,VpcId,AvailabilityZone,Tags[?Key=='Name'].Value|[0]]" --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing" && "$existing" != "None" ]]; then
            local subnet_id vpc_id az subnet_name
            read -r subnet_id vpc_id az subnet_name <<< "$existing"
            
            if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
                # Check if this is in our project's VPC (orphaned - try to delete)
                local vpc_name
                vpc_name=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" \
                    --query "Vpcs[0].Tags[?Key=='Name'].Value|[0]" --output text 2>/dev/null || echo "")
                
                if [[ "$vpc_name" == *"$project_prefix"* ]]; then
                    # This is an orphaned project subnet, try to delete
                    show_preflight_fix_attempt "InvalidSubnet.Conflict - Orphaned subnet $cidr found"
                    
                    if aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" 2>/dev/null; then
                        log "INFO" "Deleted orphaned subnet: $subnet_id ($cidr)" >&2
                        show_preflight_fix_success "InvalidSubnet.Conflict" "Deleted orphaned subnet $cidr"
                    else
                        # Can't delete, try to reuse
                        reusable_subnets+=("$cidr|$subnet_id|$vpc_id|$subnet_type|$az")
                        log "INFO" "Will attempt to reuse existing subnet: $subnet_id ($cidr)" >&2
                    fi
                else
                    # Subnet exists in another VPC - Option 1: Try to reuse it
                    reusable_subnets+=("$cidr|$subnet_id|$vpc_id|$subnet_type|$az")
                    log "INFO" "Found existing subnet $subnet_id with CIDR $cidr in VPC $vpc_id" >&2
                fi
            fi
        fi
    done
    
    # If we have subnets to potentially reuse, try Option 1
    if [[ ${#reusable_subnets[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠${NC} Found existing subnets with matching CIDRs"
        echo ""
        
        # Try Option 1: Reuse existing subnets
        if _try_subnet_reuse "${reusable_subnets[@]}"; then
            show_preflight_fix_success "InvalidSubnet.Conflict" "Configured to reuse existing subnets"
            return 0
        fi
        
        # Option 1 failed, try Option 2: Find alternative CIDRs
        echo -e "  ${YELLOW}⚠${NC} Cannot reuse existing subnets (different VPC or incompatible)"
        echo "    Attempting to find alternative unused CIDR ranges..."
        echo ""
        
        if _try_alternative_cidrs "$region" "$vpc_cidr"; then
            show_preflight_fix_success "InvalidSubnet.Conflict" "Configured alternative CIDR ranges"
            return 0
        fi
        
        # Both options failed
        _show_subnet_conflict_error "${reusable_subnets[@]}"
        return 1
    fi
    
    log "INFO" "Subnet CIDR check passed (no conflicts)" >&2
    return 0
}

# ==============================================================================
# Option 1: Try to reuse existing subnets
# ==============================================================================

_try_subnet_reuse() {
    local subnets=("$@")
    local region="${REGION:-us-east-1}"
    
    # For subnet reuse to work, all subnets must be in the SAME VPC
    # and we need to use that VPC instead of creating a new one
    
    local first_vpc=""
    local all_same_vpc=true
    local public_subnet_ids=()
    local private_subnet_ids=()
    
    for entry in "${subnets[@]}"; do
        local cidr subnet_id vpc_id subnet_type az
        IFS='|' read -r cidr subnet_id vpc_id subnet_type az <<< "$entry"
        
        if [[ -z "$first_vpc" ]]; then
            first_vpc="$vpc_id"
        elif [[ "$vpc_id" != "$first_vpc" ]]; then
            all_same_vpc=false
            break
        fi
        
        if [[ "$subnet_type" == "public" ]]; then
            public_subnet_ids+=("$subnet_id")
        else
            private_subnet_ids+=("$subnet_id")
        fi
    done
    
    if [[ "$all_same_vpc" == "true" && -n "$first_vpc" ]]; then
        # Check if VPC is usable (has internet gateway, etc.)
        local igw_id
        igw_id=$(aws ec2 describe-internet-gateways --region "$region" \
            --filters "Name=attachment.vpc-id,Values=$first_vpc" \
            --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "")
        
        if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
            # VPC has IGW, we can potentially reuse it
            echo -e "  ${GREEN}✓${NC} Option 1: Can reuse existing subnets in VPC $first_vpc"
            echo "    Public subnets: ${public_subnet_ids[*]:-none}"
            echo "    Private subnets: ${private_subnet_ids[*]:-none}"
            
            # Store configuration for later use
            SUBNET_REUSE_CONFIG="vpc_id=$first_vpc"
            if [[ ${#public_subnet_ids[@]} -gt 0 ]]; then
                SUBNET_REUSE_CONFIG+="|public_subnet_ids=${public_subnet_ids[*]}"
            fi
            if [[ ${#private_subnet_ids[@]} -gt 0 ]]; then
                SUBNET_REUSE_CONFIG+="|private_subnet_ids=${private_subnet_ids[*]}"
            fi
            
            export SUBNET_REUSE_CONFIG
            
            # Update terraform.tfvars to use existing VPC and subnets
            _update_tfvars_for_reuse "$first_vpc" "${public_subnet_ids[*]}" "${private_subnet_ids[*]}"
            
            return 0
        else
            log "INFO" "VPC $first_vpc doesn't have an Internet Gateway, cannot reuse" >&2
            return 1
        fi
    fi
    
    return 1
}

# ==============================================================================
# Option 2: Find alternative unused CIDR ranges
# ==============================================================================

_try_alternative_cidrs() {
    local region="$1"
    local vpc_cidr="$2"
    
    # Get all existing subnet CIDRs in the region
    local existing_cidrs
    existing_cidrs=$(aws ec2 describe-subnets --region "$region" \
        --query "Subnets[*].CidrBlock" --output text 2>/dev/null | tr '\t' '\n' | sort -u)
    
    # Define potential alternative CIDRs (within 10.0.0.0/16)
    local potential_public_cidrs=(
        "10.0.2.0/24"
        "10.0.3.0/24"
        "10.0.4.0/24"
        "10.0.5.0/24"
        "10.0.6.0/24"
    )
    
    local potential_private_cidrs=(
        "10.0.10.0/24"
        "10.0.13.0/24"
        "10.0.14.0/24"
        "10.0.15.0/24"
        "10.0.20.0/24"
        "10.0.21.0/24"
    )
    
    local available_public=()
    local available_private=()
    
    # Find available public CIDRs
    for cidr in "${potential_public_cidrs[@]}"; do
        if ! echo "$existing_cidrs" | grep -q "^${cidr}$"; then
            available_public+=("$cidr")
            if [[ ${#available_public[@]} -ge 2 ]]; then
                break
            fi
        fi
    done
    
    # Find available private CIDRs
    for cidr in "${potential_private_cidrs[@]}"; do
        if ! echo "$existing_cidrs" | grep -q "^${cidr}$"; then
            available_private+=("$cidr")
            if [[ ${#available_private[@]} -ge 2 ]]; then
                break
            fi
        fi
    done
    
    # Check if we found enough alternatives
    if [[ ${#available_public[@]} -ge 2 && ${#available_private[@]} -ge 2 ]]; then
        echo -e "  ${GREEN}✓${NC} Option 2: Found alternative unused CIDR ranges"
        echo "    Public subnets: ${available_public[*]}"
        echo "    Private subnets: ${available_private[*]}"
        
        # Store for later use
        SUBNET_ALTERNATIVE_CIDRS="public=${available_public[*]}|private=${available_private[*]}"
        export SUBNET_ALTERNATIVE_CIDRS
        
        # Update terraform.tfvars with alternative CIDRs
        _update_tfvars_for_alternatives "${available_public[*]}" "${available_private[*]}"
        
        return 0
    else
        log "WARN" "Could not find enough unused CIDR ranges" >&2
        log "WARN" "Available public: ${available_public[*]:-none}, Available private: ${available_private[*]:-none}" >&2
        return 1
    fi
}

# ==============================================================================
# Update terraform.tfvars for subnet reuse (Option 1)
# ==============================================================================

_update_tfvars_for_reuse() {
    local vpc_id="$1"
    local public_ids="$2"
    local private_ids="$3"
    
    local tfvars_file="${ENV_DIR}/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log "WARN" "terraform.tfvars not found, cannot update for subnet reuse" >&2
        return 1
    fi
    
    echo ""
    echo -e "  ${CYAN}Updating terraform.tfvars for subnet reuse...${NC}"
    
    # Create backup
    cp "$tfvars_file" "${tfvars_file}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Check if use_existing_vpc variable exists, if not we need to add it
    if grep -q "use_existing_vpc" "$tfvars_file"; then
        sed -i.tmp "s/use_existing_vpc.*/use_existing_vpc = true/" "$tfvars_file"
    else
        echo "" >> "$tfvars_file"
        echo "# Auto-configured by preflight checks - reusing existing infrastructure" >> "$tfvars_file"
        echo "use_existing_vpc = true" >> "$tfvars_file"
    fi
    
    if grep -q "existing_vpc_id" "$tfvars_file"; then
        sed -i.tmp "s/existing_vpc_id.*/existing_vpc_id = \"$vpc_id\"/" "$tfvars_file"
    else
        echo "existing_vpc_id = \"$vpc_id\"" >> "$tfvars_file"
    fi
    
    if [[ -n "$public_ids" ]]; then
        local public_array=$(echo "$public_ids" | sed 's/ /", "/g')
        if grep -q "existing_public_subnet_ids" "$tfvars_file"; then
            sed -i.tmp "s/existing_public_subnet_ids.*/existing_public_subnet_ids = [\"$public_array\"]/" "$tfvars_file"
        else
            echo "existing_public_subnet_ids = [\"$public_array\"]" >> "$tfvars_file"
        fi
    fi
    
    if [[ -n "$private_ids" ]]; then
        local private_array=$(echo "$private_ids" | sed 's/ /", "/g')
        if grep -q "existing_private_subnet_ids" "$tfvars_file"; then
            sed -i.tmp "s/existing_private_subnet_ids.*/existing_private_subnet_ids = [\"$private_array\"]/" "$tfvars_file"
        else
            echo "existing_private_subnet_ids = [\"$private_array\"]" >> "$tfvars_file"
        fi
    fi
    
    # Clean up temp files
    rm -f "${tfvars_file}.tmp"
    
    echo -e "  ${GREEN}✓${NC} Updated terraform.tfvars to reuse existing VPC and subnets"
    log "INFO" "Updated terraform.tfvars: use_existing_vpc=true, vpc_id=$vpc_id" >&2
    
    return 0
}

# ==============================================================================
# Update terraform.tfvars for alternative CIDRs (Option 2)
# ==============================================================================

_update_tfvars_for_alternatives() {
    local public_cidrs="$1"
    local private_cidrs="$2"
    
    local tfvars_file="${ENV_DIR}/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log "WARN" "terraform.tfvars not found, cannot update CIDRs" >&2
        return 1
    fi
    
    echo ""
    echo -e "  ${CYAN}Updating terraform.tfvars with alternative CIDRs...${NC}"
    
    # Create backup
    cp "$tfvars_file" "${tfvars_file}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Convert space-separated to terraform array format
    local public_array=$(echo "$public_cidrs" | sed 's/ /", "/g')
    local private_array=$(echo "$private_cidrs" | sed 's/ /", "/g')
    
    # Update or add public_subnet_cidrs
    if grep -q "public_subnet_cidrs" "$tfvars_file"; then
        sed -i.tmp "s|public_subnet_cidrs.*|public_subnet_cidrs = [\"$public_array\"]|" "$tfvars_file"
    else
        echo "" >> "$tfvars_file"
        echo "# Auto-configured by preflight checks - alternative CIDRs to avoid conflicts" >> "$tfvars_file"
        echo "public_subnet_cidrs = [\"$public_array\"]" >> "$tfvars_file"
    fi
    
    # Update or add private_subnet_cidrs
    if grep -q "private_subnet_cidrs" "$tfvars_file"; then
        sed -i.tmp "s|private_subnet_cidrs.*|private_subnet_cidrs = [\"$private_array\"]|" "$tfvars_file"
    else
        echo "private_subnet_cidrs = [\"$private_array\"]" >> "$tfvars_file"
    fi
    
    # Clean up temp files
    rm -f "${tfvars_file}.tmp"
    
    echo -e "  ${GREEN}✓${NC} Updated terraform.tfvars with alternative CIDR ranges"
    echo "    public_subnet_cidrs = [\"$public_array\"]"
    echo "    private_subnet_cidrs = [\"$private_array\"]"
    log "INFO" "Updated terraform.tfvars with alternative CIDRs" >&2
    
    return 0
}

# ==============================================================================
# Show detailed subnet conflict error
# ==============================================================================

_show_subnet_conflict_error() {
    local subnets=("$@")
    
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  DEPLOYMENT BLOCKED: InvalidSubnet.Conflict - Subnet CIDR conflicts${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}Conflicting Subnets:${NC}"
    
    for entry in "${subnets[@]}"; do
        local cidr subnet_id vpc_id subnet_type az
        IFS='|' read -r cidr subnet_id vpc_id subnet_type az <<< "$entry"
        echo "    - CIDR $cidr exists as $subnet_id in VPC $vpc_id ($subnet_type, $az)"
    done
    
    echo ""
    echo -e "  ${YELLOW}Resolution Options:${NC}"
    echo ""
    echo "  Option 1 (Reuse) - Failed because subnets are in different VPCs or VPC lacks IGW"
    echo "  Option 2 (Alternative CIDRs) - Failed because no unused CIDR ranges available"
    echo ""
    echo "  Manual fixes:"
    echo "    1. Delete conflicting subnets if they're unused:"
    echo "       aws ec2 delete-subnet --subnet-id <subnet-id> --region ${REGION:-us-east-1}"
    echo ""
    echo "    2. Or manually specify alternative CIDRs in terraform.tfvars:"
    echo "       public_subnet_cidrs = [\"10.0.100.0/24\", \"10.0.101.0/24\"]"
    echo "       private_subnet_cidrs = [\"10.0.110.0/24\", \"10.0.111.0/24\"]"
    echo ""
    echo "    3. Or reuse existing subnets by adding to terraform.tfvars:"
    echo "       use_existing_vpc = true"
    echo "       existing_vpc_id = \"<vpc-id>\""
    echo "       existing_public_subnet_ids = [\"<subnet-id>\"]"
    echo "       existing_private_subnet_ids = [\"<subnet-id>\"]"
    echo ""
}

# ==============================================================================
# Check 6: Orphaned IAM Roles
# ==============================================================================

check_orphaned_iam_roles() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    
    log "INFO" "Checking for orphaned IAM roles..." >&2
    
    local role_names=(
        "${project_prefix}-instance-role"
        "${project_prefix}-scheduler-lambda-role"
        "${project_prefix}-vpc-flow-logs-role"
    )
    
    local existing_roles=()
    local failed_to_delete=()
    
    for role_name in "${role_names[@]}"; do
        if aws iam get-role --role-name "$role_name" 2>/dev/null >/dev/null; then
            existing_roles+=("$role_name")
        fi
    done
    
    if [[ ${#existing_roles[@]} -gt 0 ]]; then
        show_preflight_fix_attempt "Orphaned IAM Roles found"
        
        for role_name in "${existing_roles[@]}"; do
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
                --query "AttachedPolicies[*].PolicyArn" --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role_name" \
                --query "PolicyNames" --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
            done
            
            # Remove from instance profiles
            local instance_profiles
            instance_profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
                --query "InstanceProfiles[*].InstanceProfileName" --output text 2>/dev/null || echo "")
            
            for profile in $instance_profiles; do
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role_name" 2>/dev/null || true
            done
            
            # Delete the role
            if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
                log "INFO" "Deleted orphaned IAM role: $role_name" >&2
            else
                failed_to_delete+=("$role_name")
            fi
        done
        
        if [[ ${#failed_to_delete[@]} -eq 0 ]]; then
            show_preflight_fix_success "Orphaned IAM Roles" "Deleted ${#existing_roles[@]} orphaned IAM role(s)"
        else
            # Just warn, don't fail for roles
            echo -e "  ${YELLOW}⚠${NC} Warning: Could not delete some IAM roles: ${failed_to_delete[*]}"
        fi
    fi
    
    return 0
}

# ==============================================================================
# Check 7: Orphaned Instance Profiles
# ==============================================================================

check_orphaned_instance_profiles() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    
    log "INFO" "Checking for orphaned instance profiles..." >&2
    
    local profile_name="${project_prefix}-instance-profile"
    
    if aws iam get-instance-profile --instance-profile-name "$profile_name" 2>/dev/null >/dev/null; then
        show_preflight_fix_attempt "Orphaned Instance Profile found: $profile_name"
        
        # Get roles in the instance profile
        local roles
        roles=$(aws iam get-instance-profile --instance-profile-name "$profile_name" \
            --query "InstanceProfile.Roles[*].RoleName" --output text 2>/dev/null || echo "")
        
        for role in $roles; do
            aws iam remove-role-from-instance-profile --instance-profile-name "$profile_name" --role-name "$role" 2>/dev/null || true
        done
        
        if aws iam delete-instance-profile --instance-profile-name "$profile_name" 2>/dev/null; then
            show_preflight_fix_success "Orphaned Instance Profile" "Deleted $profile_name"
        else
            echo -e "  ${YELLOW}⚠${NC} Warning: Could not delete instance profile: $profile_name"
        fi
    fi
    
    return 0
}

# ==============================================================================
# Check 8: EventBridge Rules
# ==============================================================================

check_orphaned_eventbridge_rules() {
    local project_prefix="${PROJECT_NAME:-dpg-infra}-${ENVIRONMENT:-staging}"
    local region="${REGION:-us-east-1}"
    
    log "INFO" "Checking for orphaned EventBridge rules..." >&2
    
    local rule_names=(
        "${project_prefix}-start-instances"
        "${project_prefix}-stop-instances"
    )
    
    for rule_name in "${rule_names[@]}"; do
        if aws events describe-rule --name "$rule_name" --region "$region" 2>/dev/null >/dev/null; then
            show_preflight_fix_attempt "Orphaned EventBridge Rule found: $rule_name"
            
            # Remove all targets first
            local targets
            targets=$(aws events list-targets-by-rule --rule "$rule_name" --region "$region" \
                --query "Targets[*].Id" --output text 2>/dev/null || echo "")
            
            if [[ -n "$targets" ]]; then
                aws events remove-targets --rule "$rule_name" --ids $targets --region "$region" 2>/dev/null || true
            fi
            
            if aws events delete-rule --name "$rule_name" --region "$region" 2>/dev/null; then
                log "INFO" "Deleted orphaned EventBridge rule: $rule_name" >&2
                show_preflight_fix_success "Orphaned EventBridge Rule" "Deleted $rule_name"
            else
                echo -e "  ${YELLOW}⚠${NC} Warning: Could not delete EventBridge rule: $rule_name"
            fi
        fi
    done
    
    return 0
}

# ==============================================================================
# Main Pre-flight Check Function
# ==============================================================================

run_preflight_checks() {
    local platform="${PLATFORM:-aws}"
    
    if [[ "$platform" != "aws" ]]; then
        log "INFO" "Pre-flight checks only available for AWS currently"
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Pre-flight Checks${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Checking for resource conflicts and limits before deployment..."
    echo ""
    
    local failed_checks=()
    local checks_passed=0
    local checks_fixed=0
    
    # Run all checks
    # Critical checks (will block deployment if they fail)
    
    echo -e "  ${CYAN}[1/8]${NC} Checking VPC limits..."
    if ! check_vpc_limits; then
        failed_checks+=("VpcLimitExceeded")
    else
        ((checks_passed++))
    fi
    
    echo -e "  ${CYAN}[2/8]${NC} Checking Elastic IP limits..."
    if ! check_elastic_ip_limits; then
        failed_checks+=("AddressLimitExceeded")
    else
        ((checks_passed++))
    fi
    
    echo -e "  ${CYAN}[3/8]${NC} Checking CloudWatch Log Groups..."
    if ! check_cloudwatch_log_groups; then
        failed_checks+=("ResourceAlreadyExistsException")
    else
        ((checks_passed++))
    fi
    
    echo -e "  ${CYAN}[4/8]${NC} Checking IAM Policies..."
    if ! check_iam_policies; then
        failed_checks+=("EntityAlreadyExists")
    else
        ((checks_passed++))
    fi
    
    echo -e "  ${CYAN}[5/8]${NC} Checking Subnet CIDR conflicts..."
    if ! check_subnet_conflicts; then
        failed_checks+=("InvalidSubnet.Conflict")
    else
        ((checks_passed++))
    fi
    
    # Non-critical checks (cleanup only, won't block)
    echo -e "  ${CYAN}[6/8]${NC} Checking orphaned IAM Roles..."
    check_orphaned_iam_roles
    ((checks_passed++))
    
    echo -e "  ${CYAN}[7/8]${NC} Checking orphaned Instance Profiles..."
    check_orphaned_instance_profiles
    ((checks_passed++))
    
    echo -e "  ${CYAN}[8/8]${NC} Checking orphaned EventBridge Rules..."
    check_orphaned_eventbridge_rules
    ((checks_passed++))
    
    echo ""
    
    if [[ ${#failed_checks[@]} -gt 0 ]]; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  Pre-flight Checks FAILED${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "The following issues could not be automatically resolved:"
        for check in "${failed_checks[@]}"; do
            echo -e "  ${RED}✗${NC} $check"
        done
        echo ""
        
        # Offer automatic cleanup if cleanup script exists
        local cleanup_script="${SCRIPT_DIR}/cleanup.sh"
        if [[ -f "$cleanup_script" ]]; then
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}  AUTOMATIC CLEANUP AVAILABLE${NC}"
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "A comprehensive cleanup script can attempt to remove conflicting resources"
            echo "in the safe dependency order (EC2 → NAT → VPC Endpoints → ... → VPC → IAM)."
            echo ""
            echo "To run cleanup manually:"
            echo -e "  ${CYAN}$cleanup_script --region ${REGION:-us-east-1} --prefix ${PROJECT_NAME:-dpg-infra} --dry-run${NC}"
            echo ""
            echo "To force cleanup (no prompts):"
            echo -e "  ${CYAN}$cleanup_script --region ${REGION:-us-east-1} --prefix ${PROJECT_NAME:-dpg-infra} --force${NC}"
            echo ""
        fi
        
        echo "Please resolve these issues before deploying."
        return 1
    else
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  Pre-flight Checks PASSED${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        return 0
    fi
}

# Export functions
export -f run_preflight_checks
export -f show_preflight_error
