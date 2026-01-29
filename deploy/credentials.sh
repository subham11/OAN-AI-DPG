#!/bin/bash
# ==============================================================================
# DPG Deployment - Credential Configuration
# ==============================================================================
# Functions for configuring cloud provider credentials.
# ==============================================================================

# ==============================================================================
# Main Credential Configuration
# ==============================================================================

configure_credentials() {
    local provider="$1"
    
    echo ""
    log "STEP" "Configure credentials for $(get_platform_name $provider)"
    echo ""
    
    case "$provider" in
        aws)   configure_aws_credentials ;;
        azure) configure_azure_credentials ;;
        gcp)   configure_gcp_credentials ;;
        onprem) configure_onprem_credentials ;;
    esac
}

# ==============================================================================
# AWS Credentials
# ==============================================================================

configure_aws_credentials() {
    echo -e "${BOLD}AWS Authentication${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Enter your AWS credentials to deploy the infrastructure.${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  1) Enter Access Keys"
    echo "  2) I don't have Access Keys - help me get them"
    echo ""
    
    while true; do
        read -p "  Enter your choice (1-2): " key_choice
        case "$key_choice" in
            1)
                echo ""
                read -p "  AWS Account ID: " AWS_ACCOUNT_ID
                read -p "  Access Key ID: " AWS_ACCESS_KEY
                read -sp "  Secret Access Key: " AWS_SECRET_KEY
                echo ""
                
                if [[ -z "$AWS_ACCOUNT_ID" || -z "$AWS_ACCESS_KEY" || -z "$AWS_SECRET_KEY" ]]; then
                    log "ERROR" "AWS Account ID, Access Key ID, and Secret Access Key are all required"
                    continue
                fi
                
                validate_aws_credentials_internal
                break
                ;;
            2)
                guide_create_access_keys
                break
                ;;
            *)
                echo -e "${RED}  Please enter 1 or 2${NC}"
                ;;
        esac
    done
}

guide_create_access_keys() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📋 HOW TO GET AWS ACCESS KEYS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}Step 1:${NC} Login to AWS Console"
    echo -e "  ${GREEN}Step 2:${NC} Note your Account ID (shown at top-right, 12-digit number)"
    echo -e "  ${GREEN}Step 3:${NC} Click your username (top-right corner)"
    echo -e "  ${GREEN}Step 4:${NC} Click \"Security credentials\""
    echo -e "  ${GREEN}Step 5:${NC} Scroll to \"Access keys\" section"
    echo -e "  ${GREEN}Step 6:${NC} Click \"Create access key\""
    echo -e "  ${GREEN}Step 7:${NC} Select \"Command Line Interface (CLI)\""
    echo -e "  ${GREEN}Step 8:${NC} Copy Account ID and both keys and save them securely!"
    echo ""
    
    echo -e "  Press ${GREEN}ENTER${NC} to open AWS Console..."
    read -r
    
    # Open browser
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://console.aws.amazon.com/" 2>/dev/null
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "https://console.aws.amazon.com/" 2>/dev/null
    fi
    
    echo ""
    echo -e "  ${BOLD}Once you have your Account ID and Access Keys, enter them below:${NC}"
    echo ""
    
    read -p "  AWS Account ID: " AWS_ACCOUNT_ID
    read -p "  Access Key ID: " AWS_ACCESS_KEY
    read -sp "  Secret Access Key: " AWS_SECRET_KEY
    echo ""
    
    if [[ -z "$AWS_ACCOUNT_ID" || -z "$AWS_ACCESS_KEY" || -z "$AWS_SECRET_KEY" ]]; then
        log "ERROR" "All credentials are required."
        exit 1
    fi
    
    validate_aws_credentials_internal
}

validate_aws_credentials_internal() {
    echo ""
    log "INFO" "Validating AWS credentials..."
    
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"
    
    if aws sts get-caller-identity --region "${REGION:-ap-south-1}" &> /dev/null; then
        log "SUCCESS" "AWS credentials validated successfully!"
        
        local caller_info=$(aws sts get-caller-identity --output json 2>/dev/null)
        local verified_account=$(echo "$caller_info" | jq -r '.Account' 2>/dev/null)
        local verified_arn=$(echo "$caller_info" | jq -r '.Arn' 2>/dev/null)
        
        echo -e "  ${GREEN}✓${NC} Account: $verified_account"
        echo -e "  ${GREEN}✓${NC} User:    $verified_arn"
        
        # Verify account ID matches
        if [[ "$AWS_ACCOUNT_ID" != "$verified_account" ]]; then
            log "WARN" "Account ID mismatch!"
            echo -e "  ${YELLOW}⚠${NC} Entered Account ID: $AWS_ACCOUNT_ID"
            echo -e "  ${YELLOW}⚠${NC} Verified Account ID: $verified_account"
            echo ""
            if confirm "  The Account ID doesn't match. Continue with verified ID ($verified_account)?"; then
                AWS_ACCOUNT_ID="$verified_account"
                export AWS_ACCOUNT_ID
                log "INFO" "Using verified Account ID: $AWS_ACCOUNT_ID"
            else
                log "ERROR" "Account ID verification failed"
                exit 1
            fi
        else
            export AWS_ACCOUNT_ID
            log "SUCCESS" "Account ID verified: $AWS_ACCOUNT_ID"
        fi
    else
        log "ERROR" "AWS credential validation failed"
        if confirm "  Would you like to try entering the keys again?"; then
            configure_aws_credentials
        else
            exit 1
        fi
    fi
}

# ==============================================================================
# Azure Credentials
# ==============================================================================

configure_azure_credentials() {
    echo -e "${BOLD}Azure Authentication${NC}"
    echo ""
    echo -e "${YELLOW}How to get Azure credentials:${NC}"
    echo "1. Login to Azure Portal: https://portal.azure.com"
    echo "2. Go to: Azure Active Directory → App registrations → New registration"
    echo "3. Or use Azure CLI: az ad sp create-for-rbac --name 'terraform-sp' --role Contributor"
    echo ""
    
    read -p "Subscription ID: " AZURE_SUBSCRIPTION_ID
    read -p "Tenant ID: " AZURE_TENANT_ID
    read -p "Client ID: " AZURE_CLIENT_ID
    read -sp "Client Secret: " AZURE_CLIENT_SECRET
    echo ""
    
    if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_TENANT_ID" || -z "$AZURE_CLIENT_ID" || -z "$AZURE_CLIENT_SECRET" ]]; then
        log "ERROR" "All Azure credentials are required"
        exit 1
    fi
    
    export ARM_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
    export ARM_TENANT_ID="$AZURE_TENANT_ID"
    export ARM_CLIENT_ID="$AZURE_CLIENT_ID"
    export ARM_CLIENT_SECRET="$AZURE_CLIENT_SECRET"
    
    log "INFO" "Validating Azure credentials..."
    
    if command -v az &> /dev/null; then
        if az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" &> /dev/null; then
            log "SUCCESS" "Azure credentials validated"
            local sub_name=$(az account show --query name -o tsv 2>/dev/null)
            echo -e "  Subscription: ${GREEN}$sub_name${NC}"
        else
            log "WARN" "Could not validate Azure credentials via CLI"
        fi
    else
        log "INFO" "Azure CLI not installed - credentials will be validated during deployment"
    fi
}

# ==============================================================================
# GCP Credentials
# ==============================================================================

configure_gcp_credentials() {
    echo -e "${BOLD}GCP Authentication${NC}"
    echo ""
    echo -e "${YELLOW}How to get GCP credentials:${NC}"
    echo "1. Go to GCP Console: https://console.cloud.google.com"
    echo "2. Go to: IAM & Admin → Service Accounts"
    echo "3. Create Service Account with roles: Compute Admin, IAM Admin"
    echo "4. Create and download JSON key file"
    echo ""
    
    read -p "GCP Project ID: " GCP_PROJECT_ID
    read -p "Path to Service Account JSON key file (optional): " GCP_CREDENTIALS_FILE
    
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        log "ERROR" "GCP Project ID is required"
        exit 1
    fi
    
    export GOOGLE_PROJECT="$GCP_PROJECT_ID"
    
    if [[ -n "$GCP_CREDENTIALS_FILE" && -f "$GCP_CREDENTIALS_FILE" ]]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDENTIALS_FILE"
        
        local sa_email=$(jq -r '.client_email' "$GCP_CREDENTIALS_FILE" 2>/dev/null)
        if [[ -n "$sa_email" ]]; then
            echo -e "  Service Account: ${GREEN}$sa_email${NC}"
        fi
    else
        log "INFO" "No credentials file provided - will use Application Default Credentials"
    fi
    
    log "INFO" "Validating GCP credentials..."
    
    if command -v gcloud &> /dev/null; then
        if gcloud projects describe "$GCP_PROJECT_ID" &> /dev/null; then
            log "SUCCESS" "Project access verified: $GCP_PROJECT_ID"
        else
            log "WARN" "Could not verify access to project: $GCP_PROJECT_ID"
        fi
    else
        log "INFO" "GCP CLI not installed - credentials will be validated during deployment"
    fi
}

# ==============================================================================
# On-Premise Credentials
# ==============================================================================

configure_onprem_credentials() {
    echo -e "${BOLD}On-Premise Configuration${NC}"
    echo ""
    
    read -p "Target server hostname/IP: " ONPREM_HOST
    read -p "SSH Username: " ONPREM_USER
    read -p "SSH Key path [~/.ssh/id_rsa]: " ONPREM_SSH_KEY
    ONPREM_SSH_KEY=${ONPREM_SSH_KEY:-~/.ssh/id_rsa}
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$ONPREM_SSH_KEY" "${ONPREM_USER}@${ONPREM_HOST}" "echo 'connected'" &> /dev/null; then
        log "SUCCESS" "SSH connection verified"
    else
        log "WARN" "Could not verify SSH connection. Please check credentials."
    fi
}
