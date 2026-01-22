#!/bin/bash
# ==============================================================================
# Interactive Terraform Initialization Script
# ==============================================================================
# This script guides users through the setup process, including:
# 1. Local GPU detection
# 2. Cloud provider selection (if needed)
# 3. Credential configuration
# 4. Terraform initialization
#
# Refactored into modular components:
# - init_checks.sh: Prerequisites and GPU detection
# - init_providers.sh: Cloud provider selection and credentials
# - init_terraform.sh: Terraform configuration and initialization
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source modular components
source "${SCRIPT_DIR}/init_checks.sh"
source "${SCRIPT_DIR}/init_providers.sh"
source "${SCRIPT_DIR}/init_terraform.sh"

# ==============================================================================
# Main Script
# ==============================================================================

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Multi-Cloud GPU Infrastructure - Setup Wizard            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Check prerequisites
echo -e "\n${BLUE}Step 1: Checking prerequisites...${NC}"
check_prerequisites

# Step 2: GPU Detection
echo -e "\n${BLUE}Step 2: Detecting local GPU...${NC}"
detect_local_gpu
if [ "$GPU_AVAILABLE" = true ]; then
    read -p "Do you still want to deploy to cloud? (y/N): " DEPLOY_CLOUD
    if [[ ! "$DEPLOY_CLOUD" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Using local GPU. No cloud deployment needed.${NC}"
        exit 0
    fi
fi

# Step 3: Cloud Provider Selection
select_cloud_provider

# Step 4: Configure credentials
configure_credentials

# Step 5-7: Terraform setup
execute_terraform_setup
