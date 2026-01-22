#!/bin/bash
# ==============================================================================
# Initialization - Cloud Provider Selection
# ==============================================================================
# Interactive cloud provider selection and credential configuration.
# ==============================================================================

# ==============================================================================
# Cloud Provider Selection
# ==============================================================================

select_cloud_provider() {
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
}

# ==============================================================================
# AWS Credential Configuration
# ==============================================================================

configure_aws_credentials() {
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
}

# ==============================================================================
# Azure Credential Configuration
# ==============================================================================

configure_azure_credentials() {
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
}

# ==============================================================================
# GCP Credential Configuration
# ==============================================================================

configure_gcp_credentials() {
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
}

# ==============================================================================
# Configure Credentials (Router)
# ==============================================================================

configure_credentials() {
    echo -e "\n${BLUE}Step 4: Configure credentials for $CLOUD_PROVIDER${NC}"
    
    case $CLOUD_PROVIDER in
        aws)   configure_aws_credentials ;;
        azure) configure_azure_credentials ;;
        gcp)   configure_gcp_credentials ;;
    esac
    
    echo -e "${GREEN}✓ Credentials configured${NC}"
}
