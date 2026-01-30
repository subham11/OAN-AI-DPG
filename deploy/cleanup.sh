#!/bin/bash
# ==============================================================================
# AWS Resource Cleanup Script
# ==============================================================================
# Safely removes all AWS resources created by the deployment in the correct order
# to avoid dependency conflicts.
#
# Deletion Order (safe rollback sequence):
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
# 12. Orphaned resources (CloudWatch, IAM, etc.)
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
REGION=""
PROJECT_PREFIX="dpg-infra"
ENVIRONMENT="staging"
DRY_RUN=false
FORCE=false
AWS_PROFILE="${AWS_PROFILE:-}"

# Counters
DELETED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# ==============================================================================
# Utility Functions
# ==============================================================================

print_banner() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                                           ║${NC}"
    echo -e "${RED}║                    AWS RESOURCE CLEANUP SCRIPT                            ║${NC}"
    echo -e "${RED}║                                                                           ║${NC}"
    echo -e "${RED}║           ⚠️  WARNING: This will DELETE AWS resources! ⚠️                  ║${NC}"
    echo -e "${RED}║                                                                           ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")    echo -e "${BLUE}[$timestamp]${NC} ${CYAN}INFO${NC}  $message" ;;
        "SUCCESS") echo -e "${BLUE}[$timestamp]${NC} ${GREEN}✓${NC} $message" ;;
        "WARN")    echo -e "${BLUE}[$timestamp]${NC} ${YELLOW}⚠${NC} $message" ;;
        "ERROR")   echo -e "${BLUE}[$timestamp]${NC} ${RED}✗${NC} $message" ;;
        "DELETE")  echo -e "${BLUE}[$timestamp]${NC} ${RED}🗑${NC} $message" ;;
        "SKIP")    echo -e "${BLUE}[$timestamp]${NC} ${YELLOW}→${NC} $message" ;;
        "STEP")    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                   echo -e "${YELLOW}  STEP: $message${NC}"
                   echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" ;;
    esac
}

aws_cmd() {
    local profile_arg=""
    if [[ -n "$AWS_PROFILE" ]]; then
        profile_arg="--profile $AWS_PROFILE"
    fi
    aws $profile_arg --region "$REGION" "$@"
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_wait="${3:-120}"
    local wait_interval=5
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        case "$resource_type" in
            "nat-gateway")
                local state=$(aws_cmd ec2 describe-nat-gateways --nat-gateway-ids "$resource_id" \
                    --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")
                if [[ "$state" == "deleted" ]] || [[ "$state" == "None" ]]; then
                    return 0
                fi
                ;;
            "instance")
                local state=$(aws_cmd ec2 describe-instances --instance-ids "$resource_id" \
                    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "terminated")
                if [[ "$state" == "terminated" ]]; then
                    return 0
                fi
                ;;
            "eni")
                local status=$(aws_cmd ec2 describe-network-interfaces --network-interface-ids "$resource_id" \
                    --query 'NetworkInterfaces[0].Status' --output text 2>/dev/null || echo "deleted")
                if [[ "$status" == "None" ]] || [[ -z "$status" ]]; then
                    return 0
                fi
                ;;
        esac
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        echo -n "."
    done
    return 1
}

# ==============================================================================
# Resource Discovery Functions
# ==============================================================================

get_project_vpcs() {
    aws_cmd ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=*${PROJECT_PREFIX}*" \
        --query 'Vpcs[*].VpcId' --output text 2>/dev/null || echo ""
}

get_all_vpcs_in_region() {
    aws_cmd ec2 describe-vpcs \
        --query 'Vpcs[?IsDefault==`false`].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output text 2>/dev/null || echo ""
}

# ==============================================================================
# Step 1: EC2 Instances, ASGs, and Load Balancers
# ==============================================================================

cleanup_ec2_instances() {
    log "STEP" "1/12 - Cleaning up EC2 Instances"
    
    # Find instances by project tag
    local instances=$(aws_cmd ec2 describe-instances \
        --filters "Name=tag:Name,Values=*${PROJECT_PREFIX}*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$instances" ]]; then
        log "INFO" "No EC2 instances found with project prefix"
        return 0
    fi
    
    for instance_id in $instances; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would terminate instance: $instance_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Terminating EC2 instance: $instance_id"
            if aws_cmd ec2 terminate-instances --instance-ids "$instance_id" >/dev/null 2>&1; then
                log "INFO" "Waiting for instance termination..."
                wait_for_deletion "instance" "$instance_id" 300
                log "SUCCESS" "Instance terminated: $instance_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to terminate instance: $instance_id"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

cleanup_autoscaling_groups() {
    log "INFO" "Checking for Auto Scaling Groups..."
    
    local asgs=$(aws_cmd autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${PROJECT_PREFIX}')].AutoScalingGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$asgs" ]]; then
        log "INFO" "No Auto Scaling Groups found"
        return 0
    fi
    
    for asg in $asgs; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete ASG: $asg"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting Auto Scaling Group: $asg"
            # First set desired capacity to 0
            aws_cmd autoscaling update-auto-scaling-group --auto-scaling-group-name "$asg" \
                --min-size 0 --desired-capacity 0 >/dev/null 2>&1 || true
            sleep 5
            # Then delete the ASG
            if aws_cmd autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete >/dev/null 2>&1; then
                log "SUCCESS" "Deleted ASG: $asg"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete ASG: $asg"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

cleanup_launch_templates() {
    log "INFO" "Checking for Launch Templates..."
    
    local templates=$(aws_cmd ec2 describe-launch-templates \
        --filters "Name=tag:Name,Values=*${PROJECT_PREFIX}*" \
        --query 'LaunchTemplates[*].LaunchTemplateId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$templates" ]]; then
        log "INFO" "No Launch Templates found"
        return 0
    fi
    
    for template_id in $templates; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete Launch Template: $template_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting Launch Template: $template_id"
            if aws_cmd ec2 delete-launch-template --launch-template-id "$template_id" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted Launch Template: $template_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete Launch Template: $template_id"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

cleanup_load_balancers() {
    log "INFO" "Checking for Load Balancers..."
    
    # Application/Network Load Balancers (v2)
    local albs=$(aws_cmd elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT_PREFIX}')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    for alb_arn in $albs; do
        if [[ -z "$alb_arn" ]]; then continue; fi
        
        # Delete listeners first
        local listeners=$(aws_cmd elbv2 describe-listeners --load-balancer-arn "$alb_arn" \
            --query 'Listeners[*].ListenerArn' --output text 2>/dev/null || echo "")
        for listener_arn in $listeners; do
            if [[ -n "$listener_arn" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "SKIP" "[DRY-RUN] Would delete listener: $listener_arn"
                else
                    aws_cmd elbv2 delete-listener --listener-arn "$listener_arn" >/dev/null 2>&1 || true
                fi
            fi
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete ALB/NLB: $alb_arn"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting Load Balancer: $alb_arn"
            if aws_cmd elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted Load Balancer"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete Load Balancer"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # Target Groups
    local tgs=$(aws_cmd elbv2 describe-target-groups \
        --query "TargetGroups[?contains(TargetGroupName, '${PROJECT_PREFIX}')].TargetGroupArn" \
        --output text 2>/dev/null || echo "")
    
    for tg_arn in $tgs; do
        if [[ -z "$tg_arn" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete Target Group: $tg_arn"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting Target Group: $tg_arn"
            aws_cmd elbv2 delete-target-group --target-group-arn "$tg_arn" >/dev/null 2>&1 || true
            ((DELETED_COUNT++))
        fi
    done
}

# ==============================================================================
# Step 2: NAT Gateways and Elastic IPs
# ==============================================================================

cleanup_nat_gateways() {
    log "STEP" "2/12 - Cleaning up NAT Gateways and Elastic IPs"
    
    local nat_gateways=$(aws_cmd ec2 describe-nat-gateways \
        --filter "Name=tag:Name,Values=*${PROJECT_PREFIX}*" "Name=state,Values=available,pending" \
        --query 'NatGateways[*].[NatGatewayId,NatGatewayAddresses[0].AllocationId]' --output text 2>/dev/null || echo "")
    
    if [[ -z "$nat_gateways" ]]; then
        log "INFO" "No NAT Gateways found"
    else
        echo "$nat_gateways" | while read -r nat_id alloc_id; do
            if [[ -z "$nat_id" ]]; then continue; fi
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete NAT Gateway: $nat_id (EIP: $alloc_id)"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting NAT Gateway: $nat_id"
                if aws_cmd ec2 delete-nat-gateway --nat-gateway-id "$nat_id" >/dev/null 2>&1; then
                    log "INFO" "Waiting for NAT Gateway deletion (this may take 1-2 minutes)..."
                    wait_for_deletion "nat-gateway" "$nat_id" 180
                    echo ""
                    log "SUCCESS" "NAT Gateway deleted: $nat_id"
                    ((DELETED_COUNT++))
                    
                    # Release associated EIP
                    if [[ -n "$alloc_id" ]] && [[ "$alloc_id" != "None" ]]; then
                        log "DELETE" "Releasing Elastic IP: $alloc_id"
                        sleep 5  # Wait a bit for NAT Gateway to fully release the EIP
                        if aws_cmd ec2 release-address --allocation-id "$alloc_id" >/dev/null 2>&1; then
                            log "SUCCESS" "Released Elastic IP: $alloc_id"
                            ((DELETED_COUNT++))
                        else
                            log "WARN" "Could not release EIP (may already be released): $alloc_id"
                        fi
                    fi
                else
                    log "ERROR" "Failed to delete NAT Gateway: $nat_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    fi
    
    # Also check for orphaned EIPs
    log "INFO" "Checking for orphaned Elastic IPs..."
    local orphaned_eips=$(aws_cmd ec2 describe-addresses \
        --filters "Name=tag:Name,Values=*${PROJECT_PREFIX}*" \
        --query 'Addresses[?AssociationId==`null`].AllocationId' --output text 2>/dev/null || echo "")
    
    for alloc_id in $orphaned_eips; do
        if [[ -z "$alloc_id" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would release orphaned EIP: $alloc_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Releasing orphaned Elastic IP: $alloc_id"
            if aws_cmd ec2 release-address --allocation-id "$alloc_id" >/dev/null 2>&1; then
                log "SUCCESS" "Released EIP: $alloc_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to release EIP: $alloc_id"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

# ==============================================================================
# Step 3: VPC Endpoints
# ==============================================================================

cleanup_vpc_endpoints() {
    log "STEP" "3/12 - Cleaning up VPC Endpoints"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        local endpoints=$(aws_cmd ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null || echo "")
        
        for endpoint_id in $endpoints; do
            if [[ -z "$endpoint_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete VPC Endpoint: $endpoint_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting VPC Endpoint: $endpoint_id"
                if aws_cmd ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted VPC Endpoint: $endpoint_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete VPC Endpoint: $endpoint_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    done
}

# ==============================================================================
# Step 4: VPC Peering, Transit Gateway, VPN
# ==============================================================================

cleanup_vpc_peering() {
    log "STEP" "4/12 - Cleaning up VPC Peering Connections"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        # Requester peerings
        local peerings=$(aws_cmd ec2 describe-vpc-peering-connections \
            --filters "Name=requester-vpc-info.vpc-id,Values=$vpc_id" "Name=status-code,Values=active,pending-acceptance" \
            --query 'VpcPeeringConnections[*].VpcPeeringConnectionId' --output text 2>/dev/null || echo "")
        
        for peering_id in $peerings; do
            if [[ -z "$peering_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete VPC Peering: $peering_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting VPC Peering Connection: $peering_id"
                if aws_cmd ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$peering_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted VPC Peering: $peering_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete VPC Peering: $peering_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    done
}

# ==============================================================================
# Step 5: RDS, OpenSearch, ElastiCache
# ==============================================================================

cleanup_rds() {
    log "STEP" "5/12 - Cleaning up RDS, OpenSearch, ElastiCache"
    
    # RDS Instances
    local rds_instances=$(aws_cmd rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT_PREFIX}')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    for db_id in $rds_instances; do
        if [[ -z "$db_id" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete RDS instance: $db_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting RDS instance (skip final snapshot): $db_id"
            if aws_cmd rds delete-db-instance --db-instance-identifier "$db_id" \
                --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1; then
                log "SUCCESS" "RDS deletion initiated: $db_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete RDS: $db_id"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # RDS Subnet Groups
    local rds_subnet_groups=$(aws_cmd rds describe-db-subnet-groups \
        --query "DBSubnetGroups[?contains(DBSubnetGroupName, '${PROJECT_PREFIX}')].DBSubnetGroupName" \
        --output text 2>/dev/null || echo "")
    
    for sg_name in $rds_subnet_groups; do
        if [[ -z "$sg_name" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete RDS Subnet Group: $sg_name"
        else
            log "DELETE" "Deleting RDS Subnet Group: $sg_name"
            aws_cmd rds delete-db-subnet-group --db-subnet-group-name "$sg_name" >/dev/null 2>&1 || true
        fi
    done
    
    # ElastiCache clusters
    local cache_clusters=$(aws_cmd elasticache describe-cache-clusters \
        --query "CacheClusters[?contains(CacheClusterId, '${PROJECT_PREFIX}')].CacheClusterId" \
        --output text 2>/dev/null || echo "")
    
    for cache_id in $cache_clusters; do
        if [[ -z "$cache_id" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete ElastiCache cluster: $cache_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting ElastiCache cluster: $cache_id"
            aws_cmd elasticache delete-cache-cluster --cache-cluster-id "$cache_id" >/dev/null 2>&1 || true
            ((DELETED_COUNT++))
        fi
    done
}

# ==============================================================================
# Step 6: ECS, EKS, Lambda (VPC-enabled)
# ==============================================================================

cleanup_ecs_eks_lambda() {
    log "STEP" "6/12 - Cleaning up ECS, EKS, Lambda"
    
    # Lambda functions
    local lambdas=$(aws_cmd lambda list-functions \
        --query "Functions[?contains(FunctionName, '${PROJECT_PREFIX}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    for lambda_name in $lambdas; do
        if [[ -z "$lambda_name" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete Lambda function: $lambda_name"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting Lambda function: $lambda_name"
            if aws_cmd lambda delete-function --function-name "$lambda_name" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted Lambda: $lambda_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete Lambda: $lambda_name"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # ECS Clusters (just log - full ECS cleanup is complex)
    local ecs_clusters=$(aws_cmd ecs list-clusters \
        --query "clusterArns[?contains(@, '${PROJECT_PREFIX}')]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$ecs_clusters" ]]; then
        log "WARN" "ECS clusters found - manual cleanup may be required: $ecs_clusters"
    fi
}

# ==============================================================================
# Step 7: Network Interfaces (ENIs)
# ==============================================================================

cleanup_enis() {
    log "STEP" "7/12 - Cleaning up Network Interfaces (ENIs)"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        # Get ENIs that are available (not attached)
        local enis=$(aws_cmd ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=status,Values=available" \
            --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null || echo "")
        
        for eni_id in $enis; do
            if [[ -z "$eni_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete ENI: $eni_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting ENI: $eni_id"
                if aws_cmd ec2 delete-network-interface --network-interface-id "$eni_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted ENI: $eni_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete ENI: $eni_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
        
        # Check for in-use ENIs (just warn)
        local in_use_enis=$(aws_cmd ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=status,Values=in-use" \
            --query 'NetworkInterfaces[*].[NetworkInterfaceId,Description]' --output text 2>/dev/null || echo "")
        
        if [[ -n "$in_use_enis" ]]; then
            log "WARN" "Some ENIs are still in-use (will be cleaned up when parent resources are deleted)"
        fi
    done
}

# ==============================================================================
# Step 8: Subnets
# ==============================================================================

cleanup_subnets() {
    log "STEP" "8/12 - Cleaning up Subnets"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        local subnets=$(aws_cmd ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[*].SubnetId' --output text 2>/dev/null || echo "")
        
        for subnet_id in $subnets; do
            if [[ -z "$subnet_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete Subnet: $subnet_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting Subnet: $subnet_id"
                if aws_cmd ec2 delete-subnet --subnet-id "$subnet_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted Subnet: $subnet_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete Subnet: $subnet_id (may have dependencies)"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    done
}

# ==============================================================================
# Step 9: Route Tables, Security Groups, NACLs
# ==============================================================================

cleanup_route_tables_sgs_nacls() {
    log "STEP" "9/12 - Cleaning up Route Tables, Security Groups, NACLs"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        # Route Tables (except main)
        local route_tables=$(aws_cmd ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' --output text 2>/dev/null || echo "")
        
        for rt_id in $route_tables; do
            if [[ -z "$rt_id" ]]; then continue; fi
            
            # Disassociate first
            local associations=$(aws_cmd ec2 describe-route-tables --route-table-ids "$rt_id" \
                --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text 2>/dev/null || echo "")
            
            for assoc_id in $associations; do
                if [[ -n "$assoc_id" ]]; then
                    aws_cmd ec2 disassociate-route-table --association-id "$assoc_id" >/dev/null 2>&1 || true
                fi
            done
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete Route Table: $rt_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting Route Table: $rt_id"
                if aws_cmd ec2 delete-route-table --route-table-id "$rt_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted Route Table: $rt_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete Route Table: $rt_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
        
        # Security Groups (except default)
        local sgs=$(aws_cmd ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
        
        # First, remove all ingress/egress rules that reference other SGs
        for sg_id in $sgs; do
            if [[ -z "$sg_id" ]]; then continue; fi
            
            # Get and revoke ingress rules
            local ingress_rules=$(aws_cmd ec2 describe-security-groups --group-ids "$sg_id" \
                --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo "[]")
            if [[ "$ingress_rules" != "[]" ]] && [[ -n "$ingress_rules" ]]; then
                aws_cmd ec2 revoke-security-group-ingress --group-id "$sg_id" \
                    --ip-permissions "$ingress_rules" >/dev/null 2>&1 || true
            fi
            
            # Get and revoke egress rules (except default all-traffic rule)
            local egress_rules=$(aws_cmd ec2 describe-security-groups --group-ids "$sg_id" \
                --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null || echo "[]")
            if [[ "$egress_rules" != "[]" ]] && [[ -n "$egress_rules" ]]; then
                aws_cmd ec2 revoke-security-group-egress --group-id "$sg_id" \
                    --ip-permissions "$egress_rules" >/dev/null 2>&1 || true
            fi
        done
        
        # Now delete security groups
        for sg_id in $sgs; do
            if [[ -z "$sg_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete Security Group: $sg_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting Security Group: $sg_id"
                if aws_cmd ec2 delete-security-group --group-id "$sg_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted Security Group: $sg_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete Security Group: $sg_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
        
        # Network ACLs (except default)
        local nacls=$(aws_cmd ec2 describe-network-acls \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=default,Values=false" \
            --query 'NetworkAcls[*].NetworkAclId' --output text 2>/dev/null || echo "")
        
        for nacl_id in $nacls; do
            if [[ -z "$nacl_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would delete NACL: $nacl_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Deleting Network ACL: $nacl_id"
                if aws_cmd ec2 delete-network-acl --network-acl-id "$nacl_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted NACL: $nacl_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete NACL: $nacl_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    done
}

# ==============================================================================
# Step 10: Internet Gateways
# ==============================================================================

cleanup_internet_gateways() {
    log "STEP" "10/12 - Cleaning up Internet Gateways"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        
        local igws=$(aws_cmd ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$vpc_id" \
            --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null || echo "")
        
        for igw_id in $igws; do
            if [[ -z "$igw_id" ]]; then continue; fi
            if [[ "$DRY_RUN" == "true" ]]; then
                log "SKIP" "[DRY-RUN] Would detach and delete IGW: $igw_id"
                ((SKIPPED_COUNT++))
            else
                log "DELETE" "Detaching Internet Gateway: $igw_id from $vpc_id"
                aws_cmd ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" >/dev/null 2>&1 || true
                
                log "DELETE" "Deleting Internet Gateway: $igw_id"
                if aws_cmd ec2 delete-internet-gateway --internet-gateway-id "$igw_id" >/dev/null 2>&1; then
                    log "SUCCESS" "Deleted Internet Gateway: $igw_id"
                    ((DELETED_COUNT++))
                else
                    log "ERROR" "Failed to delete Internet Gateway: $igw_id"
                    ((FAILED_COUNT++))
                fi
            fi
        done
    done
}

# ==============================================================================
# Step 11: VPCs
# ==============================================================================

cleanup_vpcs() {
    log "STEP" "11/12 - Cleaning up VPCs"
    
    local vpcs=$(get_project_vpcs)
    
    for vpc_id in $vpcs; do
        if [[ -z "$vpc_id" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete VPC: $vpc_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting VPC: $vpc_id"
            if aws_cmd ec2 delete-vpc --vpc-id "$vpc_id" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted VPC: $vpc_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete VPC: $vpc_id (may have remaining dependencies)"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

# ==============================================================================
# Step 12: Orphaned Resources (CloudWatch, IAM, EventBridge, etc.)
# ==============================================================================

cleanup_orphaned_resources() {
    log "STEP" "12/12 - Cleaning up Orphaned Resources"
    
    # CloudWatch Log Groups
    log "INFO" "Checking for CloudWatch Log Groups..."
    local log_groups=$(aws_cmd logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${PROJECT_PREFIX}" \
        --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
    
    # Also check for VPC flow logs
    local flow_log_groups=$(aws_cmd logs describe-log-groups \
        --log-group-name-prefix "${PROJECT_PREFIX}" \
        --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
    
    for lg_name in $log_groups $flow_log_groups; do
        if [[ -z "$lg_name" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete Log Group: $lg_name"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting CloudWatch Log Group: $lg_name"
            if aws_cmd logs delete-log-group --log-group-name "$lg_name" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted Log Group: $lg_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete Log Group: $lg_name"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # VPC Flow Logs
    log "INFO" "Checking for VPC Flow Logs..."
    local flow_logs=$(aws_cmd ec2 describe-flow-logs \
        --filter "Name=tag:Name,Values=*${PROJECT_PREFIX}*" \
        --query 'FlowLogs[*].FlowLogId' --output text 2>/dev/null || echo "")
    
    for fl_id in $flow_logs; do
        if [[ -z "$fl_id" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete Flow Log: $fl_id"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting VPC Flow Log: $fl_id"
            if aws_cmd ec2 delete-flow-logs --flow-log-ids "$fl_id" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted Flow Log: $fl_id"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete Flow Log: $fl_id"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # EventBridge Rules
    log "INFO" "Checking for EventBridge Rules..."
    local rules=$(aws_cmd events list-rules \
        --query "Rules[?contains(Name, '${PROJECT_PREFIX}')].Name" \
        --output text 2>/dev/null || echo "")
    
    for rule_name in $rules; do
        if [[ -z "$rule_name" ]]; then continue; fi
        
        # Remove targets first
        local targets=$(aws_cmd events list-targets-by-rule --rule "$rule_name" \
            --query 'Targets[*].Id' --output text 2>/dev/null || echo "")
        for target_id in $targets; do
            if [[ -n "$target_id" ]]; then
                aws_cmd events remove-targets --rule "$rule_name" --ids "$target_id" >/dev/null 2>&1 || true
            fi
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete EventBridge Rule: $rule_name"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting EventBridge Rule: $rule_name"
            if aws_cmd events delete-rule --name "$rule_name" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted EventBridge Rule: $rule_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete EventBridge Rule: $rule_name"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # IAM Roles (be careful - only delete project-specific ones)
    log "INFO" "Checking for IAM Roles..."
    local iam_roles=$(aws_cmd iam list-roles \
        --query "Roles[?contains(RoleName, '${PROJECT_PREFIX}')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role_name in $iam_roles; do
        if [[ -z "$role_name" ]]; then continue; fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete IAM Role: $role_name"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting IAM Role: $role_name"
            
            # Detach managed policies
            local policies=$(aws_cmd iam list-attached-role-policies --role-name "$role_name" \
                --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
            for policy_arn in $policies; do
                if [[ -n "$policy_arn" ]]; then
                    aws_cmd iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete inline policies
            local inline_policies=$(aws_cmd iam list-role-policies --role-name "$role_name" \
                --query 'PolicyNames[*]' --output text 2>/dev/null || echo "")
            for policy_name in $inline_policies; do
                if [[ -n "$policy_name" ]]; then
                    aws_cmd iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete instance profiles
            local instance_profiles=$(aws_cmd iam list-instance-profiles-for-role --role-name "$role_name" \
                --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null || echo "")
            for ip_name in $instance_profiles; do
                if [[ -n "$ip_name" ]]; then
                    aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$ip_name" --role-name "$role_name" >/dev/null 2>&1 || true
                    aws_cmd iam delete-instance-profile --instance-profile-name "$ip_name" >/dev/null 2>&1 || true
                fi
            done
            
            if aws_cmd iam delete-role --role-name "$role_name" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted IAM Role: $role_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete IAM Role: $role_name"
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    # IAM Policies
    log "INFO" "Checking for IAM Policies..."
    local iam_policies=$(aws_cmd iam list-policies --scope Local \
        --query "Policies[?contains(PolicyName, '${PROJECT_PREFIX}')].Arn" \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in $iam_policies; do
        if [[ -z "$policy_arn" ]]; then continue; fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would delete IAM Policy: $policy_arn"
            ((SKIPPED_COUNT++))
        else
            log "DELETE" "Deleting IAM Policy: $policy_arn"
            
            # Delete non-default versions first
            local versions=$(aws_cmd iam list-policy-versions --policy-arn "$policy_arn" \
                --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null || echo "")
            for version_id in $versions; do
                if [[ -n "$version_id" ]]; then
                    aws_cmd iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version_id" >/dev/null 2>&1 || true
                fi
            done
            
            if aws_cmd iam delete-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
                log "SUCCESS" "Deleted IAM Policy: $policy_arn"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete IAM Policy: $policy_arn"
                ((FAILED_COUNT++))
            fi
        fi
    done
}

# ==============================================================================
# Terraform State Cleanup
# ==============================================================================

cleanup_terraform_state() {
    log "INFO" "Checking for Terraform state files to clean..."
    
    local staging_dir="${PROJECT_ROOT}/environments/aws/staging"
    
    if [[ -f "${staging_dir}/terraform.tfstate" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "SKIP" "[DRY-RUN] Would backup and remove Terraform state"
        else
            log "INFO" "Backing up Terraform state..."
            local backup_name="terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
            cp "${staging_dir}/terraform.tfstate" "${staging_dir}/${backup_name}"
            log "SUCCESS" "State backed up to: ${backup_name}"
            
            if [[ "$FORCE" == "true" ]]; then
                log "DELETE" "Removing Terraform state file (forced)..."
                rm -f "${staging_dir}/terraform.tfstate"
                rm -f "${staging_dir}/terraform.tfstate.backup"
                log "SUCCESS" "Terraform state files removed"
            else
                log "INFO" "Terraform state preserved (use --force to remove)"
            fi
        fi
    fi
}

# ==============================================================================
# Summary
# ==============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           CLEANUP SUMMARY                                 ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Resources Deleted:${NC}  $DELETED_COUNT"
    echo -e "  ${YELLOW}→ Resources Skipped:${NC}  $SKIPPED_COUNT"
    echo -e "  ${RED}✗ Failures:${NC}           $FAILED_COUNT"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}  This was a DRY RUN. No resources were actually deleted.${NC}"
        echo -e "  ${YELLOW}  Run without --dry-run to perform actual cleanup.${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${RED}  Some resources failed to delete. This may be due to:${NC}"
        echo -e "  ${RED}    • Resources still having dependencies${NC}"
        echo -e "  ${RED}    • Insufficient permissions${NC}"
        echo -e "  ${RED}    • Resources in a transitional state${NC}"
        echo -e "  ${RED}  Try running the cleanup again after a few minutes.${NC}"
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    
    echo ""
}

# ==============================================================================
# Usage
# ==============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up AWS resources created by the deployment."
    echo ""
    echo "Options:"
    echo "  -r, --region REGION     AWS region to clean up (required)"
    echo "  -p, --prefix PREFIX     Project prefix to match (default: dpg-infra)"
    echo "  -e, --environment ENV   Environment name (default: staging)"
    echo "  --profile PROFILE       AWS profile to use"
    echo "  --dry-run               Show what would be deleted without actually deleting"
    echo "  --force                 Force deletion including Terraform state"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --region us-east-1 --dry-run"
    echo "  $0 --region us-east-1 --prefix dpg-infra --force"
    echo "  $0 --region us-west-2 --profile satya"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                PROJECT_PREFIX="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate region
    if [[ -z "$REGION" ]]; then
        echo -e "${RED}Error: Region is required${NC}"
        echo ""
        show_usage
        exit 1
    fi
    
    print_banner
    
    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  Region:      ${YELLOW}$REGION${NC}"
    echo -e "  Prefix:      ${YELLOW}$PROJECT_PREFIX${NC}"
    echo -e "  Environment: ${YELLOW}$ENVIRONMENT${NC}"
    echo -e "  AWS Profile: ${YELLOW}${AWS_PROFILE:-default}${NC}"
    echo -e "  Dry Run:     ${YELLOW}$DRY_RUN${NC}"
    echo -e "  Force:       ${YELLOW}$FORCE${NC}"
    echo ""
    
    # Confirmation
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}⚠️  This will permanently delete AWS resources in region $REGION!${NC}"
        echo -e "${RED}⚠️  Resources matching prefix '$PROJECT_PREFIX' will be deleted.${NC}"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Cleanup cancelled."
            exit 0
        fi
        echo ""
    fi
    
    # Check for existing VPCs
    log "INFO" "Discovering resources in region $REGION..."
    local project_vpcs=$(get_project_vpcs)
    
    if [[ -z "$project_vpcs" ]]; then
        log "INFO" "No VPCs found with prefix '$PROJECT_PREFIX'"
        log "INFO" "Checking for orphaned resources only..."
    else
        log "INFO" "Found VPCs: $project_vpcs"
    fi
    echo ""
    
    # Execute cleanup in safe order
    cleanup_ec2_instances
    cleanup_autoscaling_groups
    cleanup_launch_templates
    cleanup_load_balancers
    cleanup_nat_gateways
    cleanup_vpc_endpoints
    cleanup_vpc_peering
    cleanup_rds
    cleanup_ecs_eks_lambda
    cleanup_enis
    cleanup_subnets
    cleanup_route_tables_sgs_nacls
    cleanup_internet_gateways
    cleanup_vpcs
    cleanup_orphaned_resources
    cleanup_terraform_state
    
    print_summary
}

# Run main
main "$@"
