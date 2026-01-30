#!/bin/bash
# ==============================================================================
# DPG Deployment - AWS IAM Permission Checker
# ==============================================================================
# This module checks if the current AWS user/role has all required permissions
# to deploy the DPG infrastructure before running Terraform.
# 
# Compatible with Bash 3.x (macOS default) and Bash 4.x+
# ==============================================================================

# ==============================================================================
# Required Permissions Definition
# ==============================================================================

# EC2 Permissions
AWS_EC2_PERMISSIONS=(
    "ec2:RunInstances"
    "ec2:TerminateInstances"
    "ec2:StartInstances"
    "ec2:StopInstances"
    "ec2:DescribeInstances"
    "ec2:DescribeInstanceTypes"
    "ec2:CreateTags"
    "ec2:DeleteTags"
    "ec2:CreateVpc"
    "ec2:DeleteVpc"
    "ec2:DescribeVpcs"
    "ec2:ModifyVpcAttribute"
    "ec2:CreateSubnet"
    "ec2:DeleteSubnet"
    "ec2:DescribeSubnets"
    "ec2:CreateInternetGateway"
    "ec2:DeleteInternetGateway"
    "ec2:AttachInternetGateway"
    "ec2:DetachInternetGateway"
    "ec2:DescribeInternetGateways"
    "ec2:CreateRouteTable"
    "ec2:DeleteRouteTable"
    "ec2:CreateRoute"
    "ec2:DeleteRoute"
    "ec2:AssociateRouteTable"
    "ec2:DisassociateRouteTable"
    "ec2:DescribeRouteTables"
    "ec2:CreateSecurityGroup"
    "ec2:DeleteSecurityGroup"
    "ec2:DescribeSecurityGroups"
    "ec2:AuthorizeSecurityGroupIngress"
    "ec2:AuthorizeSecurityGroupEgress"
    "ec2:RevokeSecurityGroupIngress"
    "ec2:RevokeSecurityGroupEgress"
    "ec2:CreateNatGateway"
    "ec2:DeleteNatGateway"
    "ec2:DescribeNatGateways"
    "ec2:AllocateAddress"
    "ec2:ReleaseAddress"
    "ec2:DescribeAddresses"
    "ec2:CreateKeyPair"
    "ec2:DeleteKeyPair"
    "ec2:DescribeKeyPairs"
    "ec2:ImportKeyPair"
    "ec2:CreateLaunchTemplate"
    "ec2:DeleteLaunchTemplate"
    "ec2:DescribeLaunchTemplates"
    "ec2:CreateFlowLogs"
    "ec2:DeleteFlowLogs"
    "ec2:DescribeFlowLogs"
)

# IAM Permissions
AWS_IAM_PERMISSIONS=(
    "iam:CreateRole"
    "iam:DeleteRole"
    "iam:GetRole"
    "iam:TagRole"
    "iam:ListRolePolicies"
    "iam:ListAttachedRolePolicies"
    "iam:GetRolePolicy"
    "iam:PutRolePolicy"
    "iam:DeleteRolePolicy"
    "iam:AttachRolePolicy"
    "iam:DetachRolePolicy"
    "iam:CreateInstanceProfile"
    "iam:DeleteInstanceProfile"
    "iam:GetInstanceProfile"
    "iam:ListInstanceProfiles"
    "iam:AddRoleToInstanceProfile"
    "iam:RemoveRoleFromInstanceProfile"
    "iam:CreatePolicy"
    "iam:DeletePolicy"
    "iam:GetPolicy"
    "iam:GetPolicyVersion"
    "iam:ListPolicyVersions"
    "iam:PassRole"
)

# Lambda Permissions
AWS_LAMBDA_PERMISSIONS=(
    "lambda:CreateFunction"
    "lambda:DeleteFunction"
    "lambda:GetFunction"
    "lambda:GetFunctionConfiguration"
    "lambda:UpdateFunctionCode"
    "lambda:UpdateFunctionConfiguration"
    "lambda:InvokeFunction"
    "lambda:AddPermission"
    "lambda:RemovePermission"
    "lambda:GetPolicy"
    "lambda:ListFunctions"
    "lambda:ListVersionsByFunction"
    "lambda:TagResource"
    "lambda:UntagResource"
    "lambda:ListTags"
    "lambda:PublishVersion"
)

# EventBridge/CloudWatch Events Permissions
AWS_EVENTS_PERMISSIONS=(
    "events:PutRule"
    "events:DeleteRule"
    "events:DescribeRule"
    "events:EnableRule"
    "events:DisableRule"
    "events:PutTargets"
    "events:RemoveTargets"
    "events:ListTargetsByRule"
    "events:ListRules"
)

# CloudWatch Logs Permissions
AWS_LOGS_PERMISSIONS=(
    "logs:CreateLogGroup"
    "logs:DeleteLogGroup"
    "logs:CreateLogStream"
    "logs:DeleteLogStream"
    "logs:PutLogEvents"
    "logs:DescribeLogGroups"
    "logs:DescribeLogStreams"
    "logs:PutRetentionPolicy"
)

# Elastic Load Balancing Permissions
AWS_ELB_PERMISSIONS=(
    "elasticloadbalancing:CreateLoadBalancer"
    "elasticloadbalancing:DeleteLoadBalancer"
    "elasticloadbalancing:DescribeLoadBalancers"
    "elasticloadbalancing:CreateTargetGroup"
    "elasticloadbalancing:DeleteTargetGroup"
    "elasticloadbalancing:DescribeTargetGroups"
    "elasticloadbalancing:CreateListener"
    "elasticloadbalancing:DeleteListener"
    "elasticloadbalancing:DescribeListeners"
    "elasticloadbalancing:ModifyLoadBalancerAttributes"
    "elasticloadbalancing:ModifyTargetGroupAttributes"
    "elasticloadbalancing:RegisterTargets"
    "elasticloadbalancing:DeregisterTargets"
    "elasticloadbalancing:AddTags"
)

# Auto Scaling Permissions
AWS_AUTOSCALING_PERMISSIONS=(
    "autoscaling:CreateAutoScalingGroup"
    "autoscaling:UpdateAutoScalingGroup"
    "autoscaling:DeleteAutoScalingGroup"
    "autoscaling:DescribeAutoScalingGroups"
    "autoscaling:SetDesiredCapacity"
    "autoscaling:CreateLaunchConfiguration"
    "autoscaling:DeleteLaunchConfiguration"
)

# CloudWatch Metrics Permissions
AWS_CLOUDWATCH_PERMISSIONS=(
    "cloudwatch:PutMetricData"
    "cloudwatch:GetMetricData"
    "cloudwatch:GetMetricStatistics"
    "cloudwatch:ListMetrics"
    "cloudwatch:PutMetricAlarm"
    "cloudwatch:DeleteAlarms"
    "cloudwatch:DescribeAlarms"
)

# STS Permissions
AWS_STS_PERMISSIONS=(
    "sts:GetCallerIdentity"
)

# ==============================================================================
# Permission Check Functions
# ==============================================================================

# Check a single permission using iam:SimulatePrincipalPolicy
check_single_permission() {
    local action="$1"
    local arn="$2"
    
    local result=$(aws iam simulate-principal-policy \
        --policy-source-arn "$arn" \
        --action-names "$action" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null)
    
    if [[ "$result" == "allowed" ]]; then
        return 0
    else
        return 1
    fi
}

# Check a batch of permissions
check_permission_batch() {
    local arn="$1"
    shift
    local actions=("$@")
    local missing=""
    
    # AWS simulate-principal-policy can handle up to 25 actions at once
    local batch_size=20
    local total=${#actions[@]}
    
    local i=0
    while [[ $i -lt $total ]]; do
        # Build batch array manually for Bash 3.x compatibility
        local batch=()
        local j=0
        while [[ $j -lt $batch_size && $((i + j)) -lt $total ]]; do
            batch+=("${actions[$((i + j))]}")
            j=$((j + 1))
        done
        
        local result=$(aws iam simulate-principal-policy \
            --policy-source-arn "$arn" \
            --action-names ${batch[@]} \
            --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
            --output json 2>/dev/null)
        
        if [[ -n "$result" ]]; then
            # Parse JSON output to find denied permissions
            local denied=$(echo "$result" | jq -r '.[] | select(.[1] != "allowed") | .[0]' 2>/dev/null)
            if [[ -n "$denied" ]]; then
                if [[ -n "$missing" ]]; then
                    missing="$missing $denied"
                else
                    missing="$denied"
                fi
            fi
        else
            # If simulation fails, assume all in batch are missing
            for perm in "${batch[@]}"; do
                if [[ -n "$missing" ]]; then
                    missing="$missing $perm"
                else
                    missing="$perm"
                fi
            done
        fi
        
        i=$((i + batch_size))
    done
    
    echo "$missing"
}

# ==============================================================================
# Main Permission Check Function
# ==============================================================================

check_aws_permissions() {
    log "STEP" "Checking AWS IAM permissions..."
    echo ""
    
    # Get current user/role ARN
    local caller_identity=$(aws sts get-caller-identity --output json 2>/dev/null)
    if [[ -z "$caller_identity" ]]; then
        log "ERROR" "Failed to get AWS caller identity. Please check your credentials."
        return 1
    fi
    
    local arn=$(echo "$caller_identity" | jq -r '.Arn')
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    
    log "INFO" "Checking permissions for: $arn"
    echo ""
    
    # Check if we can simulate policies (meta-permission check)
    if ! aws iam simulate-principal-policy \
        --policy-source-arn "$arn" \
        --action-names "sts:GetCallerIdentity" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text &>/dev/null; then
        log "WARN" "Cannot simulate IAM policies. Using alternative permission check..."
        check_aws_permissions_alternative
        return $?
    fi
    
    # Variables to collect missing permissions
    local all_missing=""
    local has_errors=false
    
    # Helper to print permission status
    print_permission_status() {
        local group_name="$1"
        local -a group_perms=("${!2}")
        local missing_list="$3"
        local perm
        for perm in "${group_perms[@]}"; do
            if echo "$missing_list" | grep -q "\b$perm\b"; then
                printf "[ MISSING ] %s\n" "$perm"
            else
                printf "[  HAVE   ] %s\n" "$perm"
            fi
        done
        echo ""
    }

    # Check EC2 permissions
    local ec2_missing=$(check_permission_batch "$arn" "${AWS_EC2_PERMISSIONS[@]}")
    print_permission_status "EC2" AWS_EC2_PERMISSIONS[@] "$ec2_missing"
    if [[ -n "$ec2_missing" ]]; then
        all_missing="$all_missing $ec2_missing"
        has_errors=true
    fi

    # Check IAM permissions
    local iam_missing=$(check_permission_batch "$arn" "${AWS_IAM_PERMISSIONS[@]}")
    print_permission_status "IAM" AWS_IAM_PERMISSIONS[@] "$iam_missing"
    if [[ -n "$iam_missing" ]]; then
        all_missing="$all_missing $iam_missing"
        has_errors=true
    fi

    # Check Lambda permissions
    local lambda_missing=$(check_permission_batch "$arn" "${AWS_LAMBDA_PERMISSIONS[@]}")
    print_permission_status "Lambda" AWS_LAMBDA_PERMISSIONS[@] "$lambda_missing"
    if [[ -n "$lambda_missing" ]]; then
        all_missing="$all_missing $lambda_missing"
        has_errors=true
    fi

    # Check EventBridge permissions
    local events_missing=$(check_permission_batch "$arn" "${AWS_EVENTS_PERMISSIONS[@]}")
    print_permission_status "EventBridge" AWS_EVENTS_PERMISSIONS[@] "$events_missing"
    if [[ -n "$events_missing" ]]; then
        all_missing="$all_missing $events_missing"
        has_errors=true
    fi

    # Check CloudWatch Logs permissions
    local logs_missing=$(check_permission_batch "$arn" "${AWS_LOGS_PERMISSIONS[@]}")
    print_permission_status "CloudWatch Logs" AWS_LOGS_PERMISSIONS[@] "$logs_missing"
    if [[ -n "$logs_missing" ]]; then
        all_missing="$all_missing $logs_missing"
        has_errors=true
    fi

    # Check ELB permissions
    local elb_missing=$(check_permission_batch "$arn" "${AWS_ELB_PERMISSIONS[@]}")
    print_permission_status "ELB" AWS_ELB_PERMISSIONS[@] "$elb_missing"
    if [[ -n "$elb_missing" ]]; then
        all_missing="$all_missing $elb_missing"
        has_errors=true
    fi

    # Check Auto Scaling permissions
    local asg_missing=$(check_permission_batch "$arn" "${AWS_AUTOSCALING_PERMISSIONS[@]}")
    print_permission_status "Auto Scaling" AWS_AUTOSCALING_PERMISSIONS[@] "$asg_missing"
    if [[ -n "$asg_missing" ]]; then
        all_missing="$all_missing $asg_missing"
        has_errors=true
    fi

    # Check CloudWatch Metrics permissions
    local cw_missing=$(check_permission_batch "$arn" "${AWS_CLOUDWATCH_PERMISSIONS[@]}")
    print_permission_status "CloudWatch Metrics" AWS_CLOUDWATCH_PERMISSIONS[@] "$cw_missing"
    if [[ -n "$cw_missing" ]]; then
        all_missing="$all_missing $cw_missing"
        has_errors=true
    fi

    echo ""
    
    # Handle missing permissions
    if [[ "$has_errors" == true ]]; then
        show_missing_permissions $all_missing
        return 1
    else
        log "SUCCESS" "All required AWS permissions are available!"
        return 0
    fi
}

# ==============================================================================
# Alternative Permission Check (when simulate-principal-policy is not available)
# ==============================================================================

check_aws_permissions_alternative() {
    log "INFO" "Running alternative permission checks using dry-run commands..."
    echo ""
    
    local has_errors=false
    local missing_services=""
    
    # Test EC2 basic access
    echo -ne "  ${BLUE}⟳${NC} Checking EC2 access...                         \r"
    if aws ec2 describe-instances --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} EC2 describe access: Available                "
    else
        echo -e "  ${RED}✗${NC} EC2 access: Denied or error"
        missing_services="$missing_services EC2"
        has_errors=true
    fi
    
    # Test IAM basic access
    echo -ne "  ${BLUE}⟳${NC} Checking IAM access...                         \r"
    if aws iam get-user &>/dev/null || aws sts get-caller-identity &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} IAM access: Available                         "
    else
        echo -e "  ${RED}✗${NC} IAM access: Denied or error"
        missing_services="$missing_services IAM"
        has_errors=true
    fi
    
    # Test Lambda basic access
    echo -ne "  ${BLUE}⟳${NC} Checking Lambda access...                      \r"
    if aws lambda list-functions --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Lambda access: Available                      "
    else
        echo -e "  ${RED}✗${NC} Lambda access: Denied or error"
        missing_services="$missing_services Lambda"
        has_errors=true
    fi
    
    # Test EventBridge basic access
    echo -ne "  ${BLUE}⟳${NC} Checking EventBridge access...                 \r"
    if aws events list-rules --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} EventBridge access: Available                 "
    else
        echo -e "  ${RED}✗${NC} EventBridge access: Denied or error"
        missing_services="$missing_services EventBridge"
        has_errors=true
    fi
    
    # Test CloudWatch Logs basic access
    echo -ne "  ${BLUE}⟳${NC} Checking CloudWatch Logs access...             \r"
    if aws logs describe-log-groups --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} CloudWatch Logs access: Available             "
    else
        echo -e "  ${RED}✗${NC} CloudWatch Logs access: Denied or error"
        missing_services="$missing_services CloudWatch-Logs"
        has_errors=true
    fi
    
    # Test ELB basic access
    echo -ne "  ${BLUE}⟳${NC} Checking Load Balancer access...               \r"
    if aws elbv2 describe-load-balancers --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Load Balancer access: Available               "
    else
        echo -e "  ${RED}✗${NC} Load Balancer access: Denied or error"
        missing_services="$missing_services Elastic-Load-Balancing"
        has_errors=true
    fi
    
    # Test Auto Scaling basic access
    echo -ne "  ${BLUE}⟳${NC} Checking Auto Scaling access...                \r"
    if aws autoscaling describe-auto-scaling-groups --max-items 1 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Auto Scaling access: Available                "
    else
        echo -e "  ${RED}✗${NC} Auto Scaling access: Denied or error"
        missing_services="$missing_services Auto-Scaling"
        has_errors=true
    fi
    
    echo ""
    
    if [[ "$has_errors" == true ]]; then
        show_missing_services_warning $missing_services
        return 1
    else
        log "SUCCESS" "Basic AWS service access verified!"
        log "WARN" "Note: Detailed permission check unavailable. Some operations may still fail."
        return 0
    fi
}

# ==============================================================================
# Display Missing Permissions
# ==============================================================================

show_missing_permissions() {
    local missing_list="$@"
    
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ⚠  MISSING AWS PERMISSIONS${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Your AWS account is missing the following permissions required"
    echo -e "  to deploy the DPG infrastructure:"
    echo ""
    
    # Group missing permissions by service (Bash 3.x compatible)
    local current_service=""
    local sorted_perms=$(echo "$missing_list" | tr ' ' '\n' | sort | uniq)
    
    while IFS= read -r perm; do
        if [[ -z "$perm" ]]; then
            continue
        fi
        local service=$(echo "$perm" | cut -d':' -f1)
        if [[ "$service" != "$current_service" ]]; then
            if [[ -n "$current_service" ]]; then
                echo ""
            fi
            echo -e "  ${YELLOW}${service}:${NC}"
            current_service="$service"
        fi
        echo -e "    ${RED}✗${NC} $perm"
    done <<< "$sorted_perms"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📋 WHAT TO DO NEXT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Option 1: Request permissions from your AWS Administrator${NC}"
    echo ""
    echo -e "    Send your admin the policy file located at:"
    echo -e "    ${GREEN}${SCRIPT_DIR}/aws-terraform-user-policy.json${NC}"
    echo ""
    echo -e "    Ask them to attach this policy to your IAM user or role."
    echo ""
    echo -e "  ${BOLD}Option 2: Use an account with Administrator access${NC}"
    echo ""
    echo -e "    If you have access to an admin account, use those credentials"
    echo -e "    to run this deployment."
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Create a missing permissions report
    create_permissions_report $missing_list
    
    # Ask user what to do
    echo -e "  ${YELLOW}Would you like to:${NC}"
    echo ""
    echo "    1) View the required policy file"
    echo "    2) Open the policy file location"
    echo "    3) Continue anyway (may fail during Terraform apply)"
    echo "    4) Exit and get proper permissions first"
    echo ""
    
    while true; do
        read -p "  Enter your choice (1-4): " choice
        case "$choice" in
            1)
                echo ""
                echo -e "  ${BOLD}Required IAM Policy:${NC}"
                echo ""
                cat "${SCRIPT_DIR}/aws-terraform-user-policy.json"
                echo ""
                show_missing_permissions $missing_list
                ;;
            2)
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    open "${SCRIPT_DIR}"
                elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                    xdg-open "${SCRIPT_DIR}" 2>/dev/null || echo "  Location: ${SCRIPT_DIR}"
                fi
                echo ""
                echo -e "  ${GREEN}✓${NC} Opened folder containing aws-terraform-user-policy.json"
                echo ""
                read -p "  Press ENTER to continue..."
                show_missing_permissions $missing_list
                ;;
            3)
                echo ""
                log "WARN" "Continuing without required permissions. Deployment may fail."
                return 0
                ;;
            4)
                echo ""
                log "INFO" "Please obtain the required permissions and run this script again."
                exit 1
                ;;
            *)
                echo -e "  ${RED}Please enter 1, 2, 3, or 4${NC}"
                ;;
        esac
    done
}

# ==============================================================================
# Display Missing Services Warning (for alternative check)
# ==============================================================================

show_missing_services_warning() {
    local services_list="$@"
    
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ⚠  MISSING AWS SERVICE ACCESS${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Your AWS account does not have access to the following services:"
    echo ""
    for service in $services_list; do
        # Replace dashes with spaces for display
        local display_name=$(echo "$service" | tr '-' ' ')
        echo -e "    ${RED}✗${NC} $display_name"
    done
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📋 WHAT TO DO NEXT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Please contact your AWS Administrator and request access to"
    echo -e "  the missing services listed above."
    echo ""
    echo -e "  Share the policy file with your admin:"
    echo -e "  ${GREEN}${SCRIPT_DIR}/aws-terraform-user-policy.json${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "  ${YELLOW}Would you like to:${NC}"
    echo ""
    echo "    1) Continue anyway (deployment will likely fail)"
    echo "    2) Exit and get proper permissions first"
    echo ""
    
    while true; do
        read -p "  Enter your choice (1-2): " choice
        case "$choice" in
            1)
                echo ""
                log "WARN" "Continuing without required permissions. Deployment will likely fail."
                return 0
                ;;
            2)
                echo ""
                log "INFO" "Please obtain the required permissions and run this script again."
                exit 1
                ;;
            *)
                echo -e "  ${RED}Please enter 1 or 2${NC}"
                ;;
        esac
    done
}

# ==============================================================================
# Create Permissions Report
# ==============================================================================

create_permissions_report() {
    local missing_list="$@"
    local report_file="${SCRIPT_DIR}/missing-permissions-report.txt"
    
    {
        echo "================================================================================"
        echo "DPG Infrastructure - Missing AWS Permissions Report"
        echo "Generated: $(date)"
        echo "================================================================================"
        echo ""
        echo "The following AWS IAM permissions are required but missing from your account:"
        echo ""
        
        # Group by service (Bash 3.x compatible)
        local current_service=""
        local sorted_perms=$(echo "$missing_list" | tr ' ' '\n' | sort | uniq)
        
        while IFS= read -r perm; do
            if [[ -z "$perm" ]]; then
                continue
            fi
            local service=$(echo "$perm" | cut -d':' -f1)
            if [[ "$service" != "$current_service" ]]; then
                if [[ -n "$current_service" ]]; then
                    echo ""
                fi
                echo "$service:"
                current_service="$service"
            fi
            echo "  - $perm"
        done <<< "$sorted_perms"
        
        echo ""
        echo "================================================================================"
        echo "RECOMMENDED ACTION"
        echo "================================================================================"
        echo ""
        echo "Please share the following policy file with your AWS Administrator:"
        echo ""
        echo "  ${SCRIPT_DIR}/aws-terraform-user-policy.json"
        echo ""
        echo "Ask them to create an IAM policy with this content and attach it to your"
        echo "IAM user or role."
        echo ""
        echo "For more details, see: ${SCRIPT_DIR}/readme/MISSING_PERMISSIONS.md"
        echo ""
    } > "$report_file"
    
    log "INFO" "Missing permissions report saved to: $report_file"
}

# ==============================================================================
# Quick Permission Check (for use in deployment flow)
# ==============================================================================

quick_permission_check() {
    # Fast check of essential permissions only
    local arn=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    if [[ -z "$arn" ]]; then
        return 1
    fi
    
    # Check just a few critical permissions
    local critical_actions=(
        "ec2:RunInstances"
        "ec2:CreateVpc"
        "iam:CreateRole"
        "lambda:CreateFunction"
    )
    
    for action in "${critical_actions[@]}"; do
        local result=$(aws iam simulate-principal-policy \
            --policy-source-arn "$arn" \
            --action-names "$action" \
            --query 'EvaluationResults[0].EvalDecision' \
            --output text 2>/dev/null)
        
        if [[ "$result" != "allowed" ]]; then
            return 1
        fi
    done
    
    return 0
}
