#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Operations
# ==============================================================================
# Main entry point that sources modular Terraform operation files.
# ==============================================================================

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Source Modular Components
# ==============================================================================

# Terraform initialization and validation
source "${DEPLOY_DIR}/terraform_init.sh"

# Terraform plan operations
source "${DEPLOY_DIR}/terraform_plan.sh"

# Terraform apply operations
source "${DEPLOY_DIR}/terraform_apply.sh"

# Terraform destroy operations
source "${DEPLOY_DIR}/terraform_destroy.sh"

# Configuration generation
source "${DEPLOY_DIR}/terraform_config.sh"
