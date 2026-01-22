#!/bin/bash
# ==============================================================================
# Initialization - Prerequisites Check
# ==============================================================================
# Check for required tools and dependencies.
# ==============================================================================

# ==============================================================================
# Check Prerequisites
# ==============================================================================

check_prerequisites() {
    echo -e "\n${BLUE}Step 1: Checking prerequisites...${NC}"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}✗ Terraform not found. Please install Terraform >= 1.5.0${NC}"
        echo "  Visit: https://www.terraform.io/downloads"
        exit 1
    fi
    
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | sed 's/Terraform v//')
    echo -e "${GREEN}✓ Terraform found: v$TERRAFORM_VERSION${NC}"
}

# ==============================================================================
# GPU Detection
# ==============================================================================

detect_local_gpu() {
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
}
