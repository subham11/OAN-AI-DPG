#!/bin/bash
# ==============================================================================
# Post-Deployment Validation Script
# ==============================================================================
# This script validates that GPU infrastructure is properly deployed and running
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     GPU Infrastructure - Validation Script                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Change to project directory
cd "$PROJECT_DIR"

# Get Terraform outputs
echo -e "\n${BLUE}Fetching Terraform outputs...${NC}"
if ! terraform output -json > /tmp/tf_outputs.json 2>/dev/null; then
    echo -e "${RED}Failed to get Terraform outputs. Is the infrastructure deployed?${NC}"
    exit 1
fi

CLOUD_PROVIDER=$(jq -r '.cloud_provider.value // empty' /tmp/tf_outputs.json)
if [ -z "$CLOUD_PROVIDER" ]; then
    echo -e "${RED}Could not determine cloud provider from outputs${NC}"
    exit 1
fi

echo -e "${GREEN}Cloud Provider: $CLOUD_PROVIDER${NC}"

# ==============================================================================
# Validation Functions
# ==============================================================================

validate_aws() {
    echo -e "\n${BLUE}Validating AWS Infrastructure...${NC}"
    
    # Get ALB DNS
    ALB_DNS=$(jq -r '.aws_alb_dns_name.value // empty' /tmp/tf_outputs.json)
    ASG_NAME=$(jq -r '.aws_asg_name.value // empty' /tmp/tf_outputs.json)
    
    # Check ASG instances
    echo -e "\n${YELLOW}Checking Auto Scaling Group...${NC}"
    if [ -n "$ASG_NAME" ]; then
        INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
            --output table 2>/dev/null)
        
        if [ -n "$INSTANCES" ]; then
            echo -e "${GREEN}✓ ASG Instances:${NC}"
            echo "$INSTANCES"
        else
            echo -e "${RED}✗ No instances found in ASG${NC}"
        fi
    fi
    
    # Check health endpoint
    if [ -n "$ALB_DNS" ]; then
        echo -e "\n${YELLOW}Checking health endpoint...${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/health" --max-time 10 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓ Health check passed (HTTP $HTTP_CODE)${NC}"
            HEALTH_RESPONSE=$(curl -s "http://$ALB_DNS/health" --max-time 10 2>/dev/null)
            echo "  Response: $HEALTH_RESPONSE"
        else
            echo -e "${RED}✗ Health check failed (HTTP $HTTP_CODE)${NC}"
        fi
        
        # Check GPU endpoint
        echo -e "\n${YELLOW}Checking GPU status...${NC}"
        GPU_RESPONSE=$(curl -s "http://$ALB_DNS/gpu" --max-time 10 2>/dev/null)
        if [ -n "$GPU_RESPONSE" ]; then
            echo -e "${GREEN}GPU Status:${NC}"
            echo "$GPU_RESPONSE" | jq . 2>/dev/null || echo "$GPU_RESPONSE"
        fi
    fi
    
    # Check Lambda functions
    echo -e "\n${YELLOW}Checking scheduler Lambda functions...${NC}"
    LAMBDA_ARNS=$(jq -r '.aws_scheduler_lambda_arns.value // empty' /tmp/tf_outputs.json)
    if [ -n "$LAMBDA_ARNS" ]; then
        echo -e "${GREEN}✓ Scheduler functions configured${NC}"
    fi
}

validate_azure() {
    echo -e "\n${BLUE}Validating Azure Infrastructure...${NC}"
    
    RG_NAME=$(jq -r '.azure_resource_group_name.value // empty' /tmp/tf_outputs.json)
    VMSS_ID=$(jq -r '.azure_vmss_id.value // empty' /tmp/tf_outputs.json)
    LB_IP=$(jq -r '.azure_lb_ip.value // empty' /tmp/tf_outputs.json)
    
    # Check VMSS instances
    echo -e "\n${YELLOW}Checking Virtual Machine Scale Set...${NC}"
    if [ -n "$VMSS_ID" ]; then
        VMSS_NAME=$(echo "$VMSS_ID" | rev | cut -d'/' -f1 | rev)
        INSTANCES=$(az vmss list-instances \
            --resource-group "$RG_NAME" \
            --name "$VMSS_NAME" \
            --output table 2>/dev/null)
        
        if [ -n "$INSTANCES" ]; then
            echo -e "${GREEN}✓ VMSS Instances:${NC}"
            echo "$INSTANCES"
        else
            echo -e "${RED}✗ No instances found in VMSS${NC}"
        fi
    fi
    
    # Check health endpoint
    if [ -n "$LB_IP" ]; then
        echo -e "\n${YELLOW}Checking health endpoint...${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" --max-time 10 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓ Health check passed (HTTP $HTTP_CODE)${NC}"
        else
            echo -e "${YELLOW}⚠ Health check returned HTTP $HTTP_CODE${NC}"
        fi
    fi
}

validate_gcp() {
    echo -e "\n${BLUE}Validating GCP Infrastructure...${NC}"
    
    MIG_NAME=$(jq -r '.gcp_mig_name.value // empty' /tmp/tf_outputs.json)
    LB_IP=$(jq -r '.gcp_lb_ip.value // empty' /tmp/tf_outputs.json)
    
    # Check MIG instances
    echo -e "\n${YELLOW}Checking Managed Instance Group...${NC}"
    if [ -n "$MIG_NAME" ]; then
        INSTANCES=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
            --region "$(gcloud config get-value compute/region 2>/dev/null)" \
            --format="table(instance,status,currentAction)" 2>/dev/null)
        
        if [ -n "$INSTANCES" ]; then
            echo -e "${GREEN}✓ MIG Instances:${NC}"
            echo "$INSTANCES"
        else
            echo -e "${RED}✗ No instances found in MIG${NC}"
        fi
    fi
    
    # Check health endpoint
    if [ -n "$LB_IP" ]; then
        echo -e "\n${YELLOW}Checking health endpoint...${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" --max-time 10 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓ Health check passed (HTTP $HTTP_CODE)${NC}"
        else
            echo -e "${YELLOW}⚠ Health check returned HTTP $HTTP_CODE${NC}"
        fi
    fi
}

# ==============================================================================
# Common Validations
# ==============================================================================

echo -e "\n${BLUE}Running common validations...${NC}"

# Check scheduling configuration
SCHEDULING_ENABLED=$(jq -r '.scheduling_enabled.value // empty' /tmp/tf_outputs.json)
if [ "$SCHEDULING_ENABLED" = "true" ]; then
    echo -e "${GREEN}✓ Scheduling enabled${NC}"
    echo "  Start time: $(jq -r '.schedule_start_time.value' /tmp/tf_outputs.json)"
    echo "  Stop time: $(jq -r '.schedule_stop_time.value' /tmp/tf_outputs.json)"
else
    echo -e "${YELLOW}⚠ Scheduling not enabled${NC}"
fi

# Check NVIDIA configuration
echo -e "\n${YELLOW}NVIDIA Configuration:${NC}"
echo "  Driver Version: $(jq -r '.nvidia_driver_version.value' /tmp/tf_outputs.json)"
echo "  CUDA Version: $(jq -r '.cuda_version.value' /tmp/tf_outputs.json)"

# ==============================================================================
# Provider-Specific Validation
# ==============================================================================

case $CLOUD_PROVIDER in
    aws)   validate_aws ;;
    azure) validate_azure ;;
    gcp)   validate_gcp ;;
    *)     echo -e "${RED}Unknown cloud provider: $CLOUD_PROVIDER${NC}" ;;
esac

# ==============================================================================
# Summary
# ==============================================================================

echo -e "\n${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Validation Complete                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

LB_URL=$(jq -r '.load_balancer_url.value // empty' /tmp/tf_outputs.json)
if [ -n "$LB_URL" ]; then
    echo -e "Load Balancer URL: ${GREEN}$LB_URL${NC}"
fi

echo -e "\nFor more details, run: ${CYAN}terraform output${NC}"
