#!/bin/bash
# ==============================================================================
# DPG Deployment - Prerequisites & Validation
# ==============================================================================
# Functions for checking system prerequisites and validating cloud credentials.
# ==============================================================================

# ==============================================================================
# System Prerequisites
# ==============================================================================

check_prerequisites() {
    log "STEP" "Checking prerequisites..."
    local missing=()
    
    # Check Terraform
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | sed 's/Terraform v//')
        log "SUCCESS" "Terraform v$tf_version found"
    else
        missing+=("terraform")
        log "ERROR" "Terraform not found"
    fi
    
    # Check jq
    if command -v jq &> /dev/null; then
        log "SUCCESS" "jq found"
    else
        missing+=("jq")
        log "WARN" "jq not found (optional but recommended)"
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        log "SUCCESS" "curl found"
    else
        missing+=("curl")
        log "ERROR" "curl not found"
    fi
    
    # Check git (optional)
    if command -v git &> /dev/null; then
        log "SUCCESS" "git found"
    else
        log "WARN" "git not found (optional)"
    fi
    
    if [[ ${#missing[@]} -gt 0 && " ${missing[*]} " =~ " terraform " ]]; then
        echo ""
        log "ERROR" "Required dependencies missing: ${missing[*]}"
        echo ""
        echo -e "${YELLOW}Installation instructions:${NC}"
        echo ""
        
        if [[ " ${missing[*]} " =~ " terraform " ]]; then
            echo "Terraform:"
            echo "  macOS:   brew install terraform"
            echo "  Ubuntu:  sudo apt-get install terraform"
            echo "  Manual:  https://www.terraform.io/downloads"
            echo ""
        fi
        
        return 1
    fi
    
    log "SUCCESS" "All required prerequisites met"
    return 0
}

# ==============================================================================
# Cloud CLI Checks
# ==============================================================================

check_cloud_cli() {
    local provider="$1"
    
    case "$provider" in
        aws)
            if command -v aws &> /dev/null; then
                log "SUCCESS" "AWS CLI found"
                if aws sts get-caller-identity &> /dev/null; then
                    log "SUCCESS" "AWS credentials configured"
                    return 0
                else
                    log "WARN" "AWS CLI found but not authenticated"
                    return 1
                fi
            else
                log "WARN" "AWS CLI not found"
                return 1
            fi
            ;;
        azure)
            if command -v az &> /dev/null; then
                log "SUCCESS" "Azure CLI found"
                if az account show &> /dev/null; then
                    log "SUCCESS" "Azure credentials configured"
                    return 0
                else
                    log "WARN" "Azure CLI found but not authenticated"
                    return 1
                fi
            else
                log "WARN" "Azure CLI not found"
                return 1
            fi
            ;;
        gcp)
            if command -v gcloud &> /dev/null; then
                log "SUCCESS" "Google Cloud CLI found"
                if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 | grep -q "@"; then
                    log "SUCCESS" "GCP credentials configured"
                    return 0
                else
                    log "WARN" "GCP CLI found but not authenticated"
                    return 1
                fi
            else
                log "WARN" "Google Cloud CLI not found"
                return 1
            fi
            ;;
    esac
}

# ==============================================================================
# Credential Validation
# ==============================================================================

validate_cloud_credentials() {
    local provider="$1"
    
    echo ""
    log "STEP" "Validating credentials..."
    
    case "$provider" in
        aws)
            if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
                if aws sts get-caller-identity &> /dev/null; then
                    local account_id=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null)
                    local user_arn=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null)
                    log "SUCCESS" "AWS credentials validated"
                    echo -e "  Account: ${GREEN}$account_id${NC}"
                    echo -e "  Identity: ${GREEN}$user_arn${NC}"
                    return 0
                else
                    log "ERROR" "AWS credentials are invalid or expired"
                    return 1
                fi
            else
                log "WARN" "AWS credentials not set - will use Terraform to handle authentication"
                return 0
            fi
            ;;
        azure)
            if [[ -n "$ARM_CLIENT_ID" && -n "$ARM_CLIENT_SECRET" ]]; then
                log "SUCCESS" "Azure Service Principal credentials configured"
                return 0
            elif az account show &> /dev/null; then
                local sub_name=$(az account show --query "name" --output tsv 2>/dev/null)
                log "SUCCESS" "Azure CLI authenticated"
                echo -e "  Subscription: ${GREEN}$sub_name${NC}"
                return 0
            else
                log "WARN" "Azure credentials not validated - will use Terraform configuration"
                return 0
            fi
            ;;
        gcp)
            if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]] || [[ -n "$GOOGLE_CREDENTIALS" ]]; then
                log "SUCCESS" "GCP credentials configured via environment"
                return 0
            elif gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 | grep -q "@"; then
                local account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
                log "SUCCESS" "GCP authenticated"
                echo -e "  Account: ${GREEN}$account${NC}"
                return 0
            else
                log "WARN" "GCP credentials not validated - will use Terraform configuration"
                return 0
            fi
            ;;
    esac
    return 0
}
