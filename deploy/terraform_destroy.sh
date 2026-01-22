#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Destroy
# ==============================================================================
# Functions for destroying Terraform-managed infrastructure.
# ==============================================================================

# ==============================================================================
# Terraform Destroy
# ==============================================================================

terraform_destroy() {
    log "STEP" "Destroying infrastructure..."
    
    cd "$ENV_DIR"
    
    echo ""
    echo -e "${RED}WARNING: This will permanently destroy all deployed resources!${NC}"
    
    if ! confirm "Are you sure you want to destroy all infrastructure?" "N"; then
        log "INFO" "Destruction cancelled by user"
        return 1
    fi
    
    if terraform destroy -input=false -auto-approve 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Infrastructure destroyed"
        save_state "destroyed"
        return 0
    else
        log "ERROR" "Destruction failed"
        return 1
    fi
}
