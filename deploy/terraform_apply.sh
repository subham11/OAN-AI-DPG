#!/bin/bash
# ==============================================================================
# DPG Deployment - Terraform Apply
# ==============================================================================
# Functions for applying Terraform plans and deploying infrastructure.
# ==============================================================================

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
        log "SUCCESS" "Infrastructure deployed successfully!"
        save_state "deployed"
        return 0
    else
        log "ERROR" "Deployment failed"
        save_state "failed"
        return 1
    fi
}

# ==============================================================================
# Terraform Outputs
# ==============================================================================

show_outputs() {
    log "STEP" "Deployment Outputs"
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
