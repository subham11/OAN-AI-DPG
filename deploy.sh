#!/bin/bash
# ==============================================================================
# DPG Single-Click Deployment Script
# ==============================================================================
# Digital Public Goods - Streamlined Infrastructure Deployment
# 
# This script provides a single-click installation for Digital Public Goods
# infrastructure across multiple platforms:
# - Cloud Providers: AWS, Azure, GCP
# - On-Premise: Sovereign Data Centers, Local Infrastructure
#
# Features:
# - Automated dependency management
# - Interactive configuration wizard
# - Pre-configured templates for common use cases
# - Security best practices built-in
# - Non-technical user friendly
#
# Usage: ./deploy.sh [options]
#   --auto          Run in automated mode with defaults
#   --platform      Select cloud platform (aws, azure, gcp)
#   --environment   Select environment (dev, staging, prod)
#   --destroy       Tear down existing infrastructure
#   --status        Check deployment status
#   --help          Show this help message
# ==============================================================================

set -eo pipefail

# ==============================================================================
# Script Initialization
# ==============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

# ==============================================================================
# Source Module Files
# ==============================================================================

# Source all module files from deploy/ directory
source "${DEPLOY_DIR}/config.sh"
source "${DEPLOY_DIR}/utils.sh"
source "${DEPLOY_DIR}/prerequisites.sh"
source "${DEPLOY_DIR}/prompts.sh"
source "${DEPLOY_DIR}/credentials.sh"
source "${DEPLOY_DIR}/terraform.sh"

# ==============================================================================
# Main Deployment Flow
# ==============================================================================

run_interactive_deployment() {
    print_banner
    
    # Step 1: Prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Step 2: Project details
    echo ""
    log "STEP" "Project Configuration"
    read -p "Project name [dpg-infra]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-dpg-infra}
    
    read -p "Environment (dev/staging/prod) [staging]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-staging}
    
    read -p "Owner/Organization [DPG Deployment]: " OWNER
    OWNER=${OWNER:-DPG Deployment}
    
    # Step 3: Platform selection
    select_platform
    
    # Step 3.5: Set working directory
    if [[ "$PLATFORM" != "onprem" ]]; then
        if ! set_working_directory "$PLATFORM" "$ENVIRONMENT"; then
            log "ERROR" "Environment configuration not found for $PLATFORM/$ENVIRONMENT"
            echo ""
            echo "Please ensure the environment directory exists:"
            echo "  ${SCRIPT_DIR}/environments/${PLATFORM}/${ENVIRONMENT}/"
            exit 1
        fi
    fi
    
    # Step 4: Region selection
    select_region "$PLATFORM"
    
    # Step 5: Template selection
    select_template
    
    # Step 6: Configure credentials
    configure_credentials "$PLATFORM"
    
    # Step 7: Validate credentials
    if [[ "$PLATFORM" != "onprem" ]]; then
        if ! validate_cloud_credentials "$PLATFORM"; then
            log "ERROR" "Credential validation failed"
            exit 1
        fi
    fi
    
    # Step 8: Generate configuration
    generate_config "$PLATFORM" "$TEMPLATE"
    
    # Step 9: Terraform operations
    echo ""
    if ! terraform_init; then
        log "ERROR" "Setup failed at initialization"
        exit 1
    fi
    
    if ! terraform_validate; then
        log "ERROR" "Setup failed at validation"
        exit 1
    fi
    
    if ! terraform_plan; then
        log "ERROR" "Setup failed at planning"
        exit 1
    fi
    
    # Step 10: Apply
    if terraform_apply; then
        show_outputs
    else
        log "ERROR" "Deployment failed. Check $LOG_FILE for details."
        exit 1
    fi
}

run_automated_deployment() {
    print_banner
    
    log "INFO" "Running in automated mode..."
    
    if [[ -z "$PLATFORM" ]]; then
        echo ""
        echo -e "${YELLOW}Automated mode requires platform and environment.${NC}"
        echo ""
        echo "Usage: PLATFORM=aws ENVIRONMENT=staging ./deploy.sh --auto"
        echo "   Or: ./deploy.sh -p aws -e staging --auto"
        log "ERROR" "PLATFORM not specified"
        exit 1
    fi
    
    ENVIRONMENT=${ENVIRONMENT:-staging}
    
    if ! set_working_directory "$PLATFORM" "$ENVIRONMENT"; then
        log "ERROR" "Environment directory not found for $PLATFORM/$ENVIRONMENT"
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "No configuration file found: $CONFIG_FILE"
        log "INFO" "Copy terraform.tfvars.example to terraform.tfvars and fill in values"
        exit 1
    fi
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    terraform_init || exit 1
    terraform_validate || exit 1
    terraform_plan || exit 1
    
    cd "$ENV_DIR"
    if terraform apply -input=false -auto-approve tfplan 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Infrastructure deployed successfully!"
        save_state "deployed"
        show_outputs
    else
        log "ERROR" "Deployment failed"
        save_state "failed"
        exit 1
    fi
}

# ==============================================================================
# Entry Point
# ==============================================================================

main() {
    # Parse arguments
    local AUTO_MODE=false
    local DESTROY_MODE=false
    local STATUS_MODE=false
    local VALIDATE_MODE=false
    local PLAN_MODE=false
    local TEMPLATE_ARG=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --platform|-p)
                PLATFORM="$2"
                shift 2
                ;;
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --template)
                TEMPLATE_ARG="$2"
                shift 2
                ;;
            --destroy)
                DESTROY_MODE=true
                shift
                ;;
            --status)
                STATUS_MODE=true
                shift
                ;;
            --validate)
                VALIDATE_MODE=true
                shift
                ;;
            --plan)
                PLAN_MODE=true
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
    
    # Initialize log
    echo "=== DPG Deployment Log - $(date) ===" >> "$LOG_FILE"
    
    # Helper to require platform and environment
    require_platform_env() {
        if [[ -z "$PLATFORM" ]]; then
            echo -e "${RED}Error: Platform required for this mode${NC}"
            echo "Usage: ./deploy.sh --platform aws --environment staging $1"
            exit 1
        fi
        ENVIRONMENT=${ENVIRONMENT:-staging}
        if ! set_working_directory "$PLATFORM" "$ENVIRONMENT"; then
            exit 1
        fi
    }
    
    # Execute based on mode
    if [[ "$STATUS_MODE" == true ]]; then
        show_status
    elif [[ "$DESTROY_MODE" == true ]]; then
        print_banner
        require_platform_env "--destroy"
        terraform_destroy
    elif [[ "$VALIDATE_MODE" == true ]]; then
        print_banner
        require_platform_env "--validate"
        check_prerequisites || exit 1
        terraform_init || exit 1
        terraform_validate
    elif [[ "$PLAN_MODE" == true ]]; then
        print_banner
        require_platform_env "--plan"
        check_prerequisites || exit 1
        terraform_init || exit 1
        terraform_validate || exit 1
        terraform_plan
    elif [[ "$AUTO_MODE" == true ]]; then
        run_automated_deployment
    else
        run_interactive_deployment
    fi
}

# Run main
main "$@"
