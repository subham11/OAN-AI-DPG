#!/bin/bash
# ==============================================================================
# Interactive Terraform Initialization Script
# ==============================================================================
# This script guides users through the setup process, including:
# 1. Local GPU detection
# 2. Cloud provider selection (if needed)
# 3. Credential configuration
# 4. Terraform initialization
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Multi-Cloud GPU Infrastructure - Setup Wizard            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ==============================================================================
# Step 1: Check prerequisites
# ==============================================================================
echo -e "\n${BLUE}Step 1: Checking prerequisites...${NC}"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Terraform not found. Please install Terraform >= 1.5.0${NC}"
    echo "  Visit: https://www.terraform.io/downloads"
    exit 1
fi

TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | sed 's/Terraform v//')
echo -e "${GREEN}✓ Terraform found: v$TERRAFORM_VERSION${NC}"

# ==============================================================================
# Step 2: GPU Detection
# ==============================================================================
echo -e "\n${BLUE}Step 2: Detecting local GPU...${NC}"

if [ -f "$SCRIPT_DIR/detect_gpu.sh" ]; then
    chmod +x "$SCRIPT_DIR/detect_gpu.sh"
    
    if "$SCRIPT_DIR/detect_gpu.sh" /tmp/gpu_detection.json; then
        GPU_AVAILABLE=true
        echo -e "\n${GREEN}Local GPU detected and available!${NC}"
        read -p "Do you still want to deploy to cloud? (y/N): " DEPLOY_CLOUD
        if [[ ! "$DEPLOY_CLOUD" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Using local GPU. No cloud deployment needed.${NC}"
            exit 0
        fi
    else
        GPU_AVAILABLE=false
        echo -e "\n${YELLOW}No local GPU available. Cloud deployment required.${NC}"
    fi
else
    echo -e "${YELLOW}GPU detection script not found. Proceeding with cloud setup.${NC}"
    GPU_AVAILABLE=false
fi

# ==============================================================================
# Step 3: Cloud Provider Selection
# ==============================================================================
echo -e "\n${BLUE}Step 3: Select cloud provider${NC}"
echo "Available options:"
echo "  1) AWS (g5.4xlarge with NVIDIA A10G)"
echo "  2) Azure (Standard_NV36ads_A10_v5 with NVIDIA A10)"
echo "  3) GCP (n1-standard-16 with NVIDIA L4)"

while true; do
    read -p "Enter your choice (1-3): " CLOUD_CHOICE
    case $CLOUD_CHOICE in
        1) CLOUD_PROVIDER="aws"; break;;
        2) CLOUD_PROVIDER="azure"; break;;
        3) CLOUD_PROVIDER="gcp"; break;;
        *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}";;
    esac
done

echo -e "${GREEN}Selected: $CLOUD_PROVIDER${NC}"

# ==============================================================================
# Step 4: Collect credentials
# ==============================================================================
echo -e "\n${BLUE}Step 4: Configure credentials for $CLOUD_PROVIDER${NC}"

case $CLOUD_PROVIDER in
    aws)
        echo -e "\n${YELLOW}AWS Credentials${NC}"
        echo "You can provide credentials via:"
        echo "  1) Environment variables (recommended)"
        echo "  2) AWS CLI profile"
        echo "  3) Manual entry"
        
        read -p "Choose method (1-3): " AWS_METHOD
        
        case $AWS_METHOD in
            1)
                echo -e "\nSet these environment variables before running terraform:"
                echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
                echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
                echo "  export AWS_DEFAULT_REGION='ap-south-1'"
                
                if [ -z "$AWS_ACCESS_KEY_ID" ]; then
                    read -p "Enter AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
                    export AWS_ACCESS_KEY_ID
                fi
                if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
                    read -sp "Enter AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
                    echo
                    export AWS_SECRET_ACCESS_KEY
                fi
                read -p "Enter AWS_REGION [ap-south-1]: " AWS_REGION
                AWS_REGION=${AWS_REGION:-ap-south-1}
                export AWS_DEFAULT_REGION=$AWS_REGION
                ;;
            2)
                echo "Using existing AWS CLI profile..."
                if ! command -v aws &> /dev/null; then
                    echo -e "${RED}AWS CLI not found. Please install it or use another method.${NC}"
                    exit 1
                fi
                aws sts get-caller-identity || { echo -e "${RED}AWS authentication failed${NC}"; exit 1; }
                ;;
            3)
                read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
                read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
                echo
                read -p "Enter AWS Region [ap-south-1]: " AWS_REGION
                AWS_REGION=${AWS_REGION:-ap-south-1}
                ;;
        esac
        ;;
        
    azure)
        echo -e "\n${YELLOW}Azure Credentials${NC}"
        echo "You need a Service Principal with Contributor access."
        
        read -p "Enter Azure Subscription ID: " AZURE_SUBSCRIPTION_ID
        read -p "Enter Azure Client ID (App ID): " AZURE_CLIENT_ID
        read -sp "Enter Azure Client Secret: " AZURE_CLIENT_SECRET
        echo
        read -p "Enter Azure Tenant ID: " AZURE_TENANT_ID
        read -p "Enter Azure Location [centralindia]: " AZURE_LOCATION
        AZURE_LOCATION=${AZURE_LOCATION:-centralindia}
        
        export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
        export ARM_CLIENT_ID=$AZURE_CLIENT_ID
        export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
        export ARM_TENANT_ID=$AZURE_TENANT_ID
        ;;
        
    gcp)
        echo -e "\n${YELLOW}GCP Credentials${NC}"
        echo "You need a service account JSON key file."
        
        read -p "Enter GCP Project ID: " GCP_PROJECT_ID
        read -p "Enter path to service account JSON file: " GCP_CREDENTIALS_FILE
        read -p "Enter GCP Region [asia-south1]: " GCP_REGION
        GCP_REGION=${GCP_REGION:-asia-south1}
        
        if [ ! -f "$GCP_CREDENTIALS_FILE" ]; then
            echo -e "${RED}Service account file not found: $GCP_CREDENTIALS_FILE${NC}"
            exit 1
        fi
        
        export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
        export GOOGLE_PROJECT=$GCP_PROJECT_ID
        ;;
esac

echo -e "${GREEN}✓ Credentials configured${NC}"

# ==============================================================================
# Step 5: Generate terraform.tfvars
# ==============================================================================
echo -e "\n${BLUE}Step 5: Generating terraform.tfvars${NC}"

read -p "Enter project name [gpu-infra]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-gpu-infra}

read -p "Enter environment (dev/staging/prod) [dev]: " ENVIRONMENT
ENVIRONMENT=${ENVIRONMENT:-dev}

read -p "Enable scheduled start/stop? (Y/n): " ENABLE_SCHEDULING
ENABLE_SCHEDULING=${ENABLE_SCHEDULING:-Y}
if [[ "$ENABLE_SCHEDULING" =~ ^[Yy]$ ]]; then
    ENABLE_SCHEDULING="true"
else
    ENABLE_SCHEDULING="false"
fi

# Generate SSH key if needed
read -p "Do you have an SSH public key? (y/N): " HAS_SSH_KEY
if [[ "$HAS_SSH_KEY" =~ ^[Yy]$ ]]; then
    read -p "Enter path to SSH public key: " SSH_KEY_PATH
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH" 2>/dev/null || echo "")
else
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$PROJECT_DIR/gpu-infra-key" -N "" -q
    SSH_PUBLIC_KEY=$(cat "$PROJECT_DIR/gpu-infra-key.pub")
    echo -e "${GREEN}SSH key generated: $PROJECT_DIR/gpu-infra-key${NC}"
fi

# Create terraform.tfvars
cat > "$PROJECT_DIR/terraform.tfvars" << EOF
# Generated by init.sh at $(date)

project_name   = "$PROJECT_NAME"
environment    = "$ENVIRONMENT"
cloud_provider = "$CLOUD_PROVIDER"

# Scheduling
enable_scheduling = $ENABLE_SCHEDULING

# SSH Key
ssh_public_key = "$SSH_PUBLIC_KEY"
EOF

# Add cloud-specific variables
case $CLOUD_PROVIDER in
    aws)
        cat >> "$PROJECT_DIR/terraform.tfvars" << EOF

# AWS Configuration
aws_region = "${AWS_REGION:-ap-south-1}"
aws_availability_zones = ["${AWS_REGION:-ap-south-1}a", "${AWS_REGION:-ap-south-1}b"]
EOF
        ;;
    azure)
        cat >> "$PROJECT_DIR/terraform.tfvars" << EOF

# Azure Configuration
azure_location = "${AZURE_LOCATION:-centralindia}"
EOF
        ;;
    gcp)
        cat >> "$PROJECT_DIR/terraform.tfvars" << EOF

# GCP Configuration
gcp_project_id = "$GCP_PROJECT_ID"
gcp_region     = "${GCP_REGION:-asia-south1}"
gcp_zone       = "${GCP_REGION:-asia-south1}-a"
EOF
        ;;
esac

echo -e "${GREEN}✓ terraform.tfvars generated${NC}"

# ==============================================================================
# Step 6: Initialize Terraform
# ==============================================================================
echo -e "\n${BLUE}Step 6: Initializing Terraform${NC}"

cd "$PROJECT_DIR"
terraform init

echo -e "${GREEN}✓ Terraform initialized${NC}"

# ==============================================================================
# Step 7: Plan
# ==============================================================================
echo -e "\n${BLUE}Step 7: Creating execution plan${NC}"

terraform plan -out=tfplan

echo -e "\n${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "To deploy the infrastructure, run:"
echo -e "  ${GREEN}cd $PROJECT_DIR && terraform apply tfplan${NC}"
echo ""
echo -e "To destroy the infrastructure later, run:"
echo -e "  ${RED}terraform destroy${NC}"
