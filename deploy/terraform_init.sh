#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Init & Validate
# ==============================================================================
# Functions for Terraform initialization and validation.
# ==============================================================================

# ==============================================================================
# Terraform Init
# ==============================================================================

terraform_init() {
    log "STEP" "Initializing Terraform..."
    
    if [[ -z "$ENV_DIR" || ! -d "$ENV_DIR" ]]; then
        log "ERROR" "Environment directory not set. Call set_working_directory first."
        return 1
    fi
    
    cd "$ENV_DIR"
    log "INFO" "Working directory: $ENV_DIR"
    
    if terraform init -input=false 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Terraform initialized"
        return 0
    else
        log "ERROR" "Terraform initialization failed"
        return 1
    fi
}

# ==============================================================================
# Terraform Validate
# ==============================================================================

terraform_validate() {
    log "STEP" "Validating configuration..."
    
    cd "$ENV_DIR"
    
    if terraform validate 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Configuration is valid"
        return 0
    else
        log "ERROR" "Configuration validation failed"
        return 1
    fi
}
