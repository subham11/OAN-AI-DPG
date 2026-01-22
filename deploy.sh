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
#   --template      Use a pre-configured template
#   --destroy       Tear down existing infrastructure
#   --status        Check deployment status
#   --help          Show this help message
# ==============================================================================

set -eo pipefail

# ==============================================================================
# Configuration & Constants
# ==============================================================================
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/terraform.tfvars"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Instance Configuration Variables
INSTANCE_TYPE=""
MACHINE_TYPE=""
GPU_TYPE=""
GPU_COUNT=1
VOLUME_SIZE=100

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Platform descriptions
get_platform_name() {
    case "$1" in
        aws) echo "Amazon Web Services (AWS)" ;;
        azure) echo "Microsoft Azure" ;;
        gcp) echo "Google Cloud Platform (GCP)" ;;
        onprem) echo "On-Premise / Sovereign Data Center" ;;
        *) echo "$1" ;;
    esac
}

# Region configurations (India primary, US fallback)
get_india_region() {
    case "$1" in
        aws) echo "ap-south-1" ;;
        azure) echo "centralindia" ;;
        gcp) echo "asia-south1" ;;
        *) echo "" ;;
    esac
}

get_us_region() {
    case "$1" in
        aws) echo "us-east-1" ;;
        azure) echo "eastus" ;;
        gcp) echo "us-east1" ;;
        *) echo "" ;;
    esac
}

# Template descriptions
get_template_desc() {
    case "$1" in
        omniasr-standard) echo "OmniASR Standard - Single GPU (A10G/L4 24GB)" ;;
        omniasr-highmem) echo "OmniASR High Memory - Single GPU with extra RAM" ;;
        omniasr-multigpu) echo "OmniASR Multi-GPU - Multiple GPUs for high throughput" ;;
        omniasr-premium) echo "OmniASR Premium - A100 GPU for maximum performance" ;;
        omniasr-ultra) echo "OmniASR Ultra - A100 80GB for research" ;;
        onprem-standard) echo "On-Premise Standard - Single GPU deployment" ;;
        onprem-ha) echo "On-Premise HA - Multi-node with load balancing" ;;
        minimal) echo "Minimal setup - Single instance, basic configuration" ;;
        standard) echo "Standard setup - Auto-scaling, load balancer, scheduling" ;;
        production) echo "Production setup - HA, monitoring, security hardened" ;;
        development) echo "Development setup - Cost-optimized for testing" ;;
        custom) echo "Custom configuration" ;;
        *) echo "$1" ;;
    esac
}

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "INFO")  echo -e "${BLUE}ℹ ${NC}$message" ;;
        "SUCCESS") echo -e "${GREEN}✓ ${NC}$message" ;;
        "WARN")  echo -e "${YELLOW}⚠ ${NC}$message" ;;
        "ERROR") echo -e "${RED}✗ ${NC}$message" ;;
        "STEP")  echo -e "${CYAN}▶ ${NC}${BOLD}$message${NC}" ;;
    esac
}

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║          ___    _    _   _            _    ___                            ║
║         / _ \  / \  | \ | |          / \  |_ _|                           ║
║        | | | |/ _ \ |  \| |  _____  / _ \  | |                            ║
║        | |_| / ___ \| |\  | |_____|| ___ | | |                            ║
║         \___/_/   \_\_| \_|        |_/   \|___|                           ║
║                                                                           ║
║         Digital Public Goods - Single Click Deployment                    ║
║                OpenAgriNet - The Next GEN Agri Tech                       ║
║                          Version 1.0.0                                    ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_help() {
    cat << EOF
DPG Single-Click Deployment Script v${VERSION}

Usage: $0 [OPTIONS]

Options:
  --auto              Run in automated mode using defaults or existing config
  --template NAME     Use a pre-configured template (minimal, standard, production, development)
  --destroy           Destroy existing infrastructure
  --status            Show current deployment status
  --validate          Validate configuration without deploying
  --plan              Show deployment plan without applying
  --help              Show this help message

Examples:
  $0                  Interactive deployment wizard
  $0 --template standard --auto
  $0 --destroy
  $0 --status

Templates:
  minimal      - Single instance, basic setup (cost-effective)
  standard     - Auto-scaling, load balancer, scheduling (recommended)
  production   - High availability, monitoring, security hardened
  development  - Development/testing optimized

Supported Platforms:
  - AWS (Amazon Web Services)
  - Azure (Microsoft Azure)  
  - GCP (Google Cloud Platform)
  - On-Premise (Sovereign Data Centers)

For more information, visit: https://github.com/openagri/dpg-terraform-gpu-infra
EOF
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

confirm() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        read -p "$message [Y/n]: " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -p "$message [y/N]: " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}

save_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
}

get_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "not_deployed"
    fi
}

# ==============================================================================
# Prerequisite Checks
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

# Validate credentials after user enters them
validate_cloud_credentials() {
    local provider="$1"
    
    echo ""
    log "STEP" "Validating credentials..."
    
    case "$provider" in
        aws)
            # Check if we have access keys configured
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

# ==============================================================================
# Platform Selection
# ==============================================================================

select_platform() {
    echo ""
    log "STEP" "Select deployment platform"
    echo ""
    echo -e "${BOLD}Available Platforms:${NC}"
    echo ""
    echo "  ${CYAN}Cloud Providers:${NC}"
    echo "    1) AWS    - Amazon Web Services (Mumbai: ap-south-1)"
    echo "    2) Azure  - Microsoft Azure (Central India: centralindia)"  
    echo "    3) GCP    - Google Cloud Platform (Mumbai: asia-south1)"
    echo ""
    echo "  ${CYAN}On-Premise / Sovereign:${NC}"
    echo "    4) On-Premise  - Local infrastructure / Sovereign Data Center"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-4): " choice
        case "$choice" in
            1) PLATFORM="aws"; break ;;
            2) PLATFORM="azure"; break ;;
            3) PLATFORM="gcp"; break ;;
            4) PLATFORM="onprem"; break ;;
            *) echo -e "${RED}Invalid choice. Please enter 1-4.${NC}" ;;
        esac
    done
    
    log "SUCCESS" "Selected platform: $(get_platform_name $PLATFORM)"
}

# ==============================================================================
# Region Selection
# ==============================================================================

select_region() {
    local provider="$1"
    
    if [[ "$provider" == "onprem" ]]; then
        log "INFO" "On-premise deployment - no region selection needed"
        return
    fi
    
    local india_region=$(get_india_region "$provider")
    local us_region=$(get_us_region "$provider")
    
    echo ""
    log "STEP" "Select deployment region"
    echo ""
    echo -e "${BOLD}Region Preference:${NC}"
    echo "  1) India (Primary) - $india_region"
    echo "  2) US (Alternative) - $us_region"
    echo "  3) Custom region"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-3) [1]: " choice
        choice=${choice:-1}
        case "$choice" in
            1) 
                REGION="$india_region"
                PREFERRED_REGION="india"
                break 
                ;;
            2) 
                REGION="$us_region"
                PREFERRED_REGION="us"
                break 
                ;;
            3) 
                read -p "Enter custom region: " REGION
                PREFERRED_REGION="custom"
                break 
                ;;
            *) echo -e "${RED}Invalid choice. Please enter 1-3.${NC}" ;;
        esac
    done
    
    log "SUCCESS" "Selected region: $REGION"
}

# ==============================================================================
# Template Selection with GPU Awareness
# ==============================================================================

show_model_requirements() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📊 omniASR_LLM_7B_v2 Model Requirements${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Model Specifications:${NC}"
    echo -e "  ├─ Model Name:       omniASR_LLM_7B_v2"
    echo -e "  ├─ Parameters:       7.8 Billion (~7.8B)"
    echo -e "  ├─ Model Size:       30.0 GiB (Disk)"
    echo -e "  ├─ GPU Memory:       ${YELLOW}~17 GiB required${NC}"
    echo -e "  ├─ Inference Speed:  0.092 (~1x real-time)"
    echo -e "  ├─ Max Audio Length: 40 seconds"
    echo -e "  └─ Languages:        1,600+ supported"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🖥️  Hardware Requirements${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    printf "  ${BOLD}%-15s %-25s %-25s${NC}\n" "Component" "Minimum" "Recommended"
    echo -e "  ─────────────────────────────────────────────────────────────────"
    printf "  %-15s %-25s %-25s\n" "GPU" "NVIDIA 20+ GB VRAM" "NVIDIA A100 (40/80GB)"
    printf "  %-15s %-25s %-25s\n" "GPU Memory" "~17 GiB" "24+ GiB"
    printf "  %-15s %-25s %-25s\n" "Precision" "BF16 (bfloat16)" "BF16"
    printf "  %-15s %-25s %-25s\n" "RAM" "32 GB" "64+ GB"
    printf "  %-15s %-25s %-25s\n" "Storage" "50 GB free" "100+ GB"
    echo ""
}

show_compatible_gpus() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ✅ Compatible GPUs${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} NVIDIA A100 (40GB/80GB) - ${YELLOW}Recommended${NC}"
    echo -e "  ${GREEN}✓${NC} NVIDIA A10G (24GB)"
    echo -e "  ${GREEN}✓${NC} NVIDIA L4 (24GB)"
    echo -e "  ${GREEN}✓${NC} NVIDIA RTX 4090 (24GB)"
    echo -e "  ${GREEN}✓${NC} NVIDIA A6000 (48GB)"
    echo ""
    echo -e "  ${YELLOW}⚠${NC} NVIDIA T4 (16GB) - ${RED}Insufficient VRAM${NC}"
    echo -e "  ${YELLOW}⚠${NC} NVIDIA V100 (16GB) - ${RED}Insufficient VRAM${NC}"
    echo ""
}

show_gpu_instance_options() {
    local provider="$1"
    local region="$2"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🚀 Available GPU Instances for $(get_platform_name $provider)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    case "$provider" in
        aws)
            echo -e "  ${BOLD}Region: ${CYAN}$region${NC}"
            echo ""
            printf "  ${BOLD}%-5s %-20s %-15s %-10s %-10s %-15s${NC}\n" "#" "Instance Type" "GPU" "VRAM" "vCPUs" "RAM"
            echo -e "  ────────────────────────────────────────────────────────────────────────────"
            
            if [[ "$region" == "ap-south-1" ]]; then
                echo -e "  ${GREEN}1)${NC}   g5.4xlarge          NVIDIA A10G    24 GB     16        64 GB"
                echo -e "  ${GREEN}2)${NC}   g5.8xlarge          NVIDIA A10G    24 GB     32        128 GB"
                echo -e "  ${GREEN}3)${NC}   g5.12xlarge         NVIDIA A10G x4 96 GB     48        192 GB"
                echo -e "  ${YELLOW}4)${NC}   p3.2xlarge          NVIDIA V100    ${RED}16 GB${NC}     8         61 GB  ${RED}(Insufficient)${NC}"
                echo ""
                echo -e "  ${YELLOW}Note: A100 instances (p4d/p5) not available in ap-south-1${NC}"
                echo -e "  ${YELLOW}      Select US region for A100 access${NC}"
            else
                echo -e "  ${GREEN}1)${NC}   g5.4xlarge          NVIDIA A10G    24 GB     16        64 GB"
                echo -e "  ${GREEN}2)${NC}   g5.8xlarge          NVIDIA A10G    24 GB     32        128 GB"
                echo -e "  ${GREEN}3)${NC}   p4d.24xlarge        NVIDIA A100 x8 320 GB    96        1152 GB  ${YELLOW}(Premium)${NC}"
                echo -e "  ${GREEN}4)${NC}   p5.48xlarge         NVIDIA H100 x8 640 GB    192       2048 GB  ${YELLOW}(Ultra Premium)${NC}"
            fi
            ;;
        azure)
            echo -e "  ${BOLD}Region: ${CYAN}$region${NC}"
            echo ""
            printf "  ${BOLD}%-5s %-28s %-15s %-10s %-10s %-10s${NC}\n" "#" "Instance Type" "GPU" "VRAM" "vCPUs" "RAM"
            echo -e "  ────────────────────────────────────────────────────────────────────────────"
            
            if [[ "$region" == "centralindia" ]]; then
                echo -e "  ${GREEN}1)${NC}   Standard_NV36ads_A10_v5   NVIDIA A10     24 GB     36        440 GB"
                echo -e "  ${GREEN}2)${NC}   Standard_NC24ads_A100_v4  NVIDIA A100    80 GB     24        220 GB"
                echo -e "  ${YELLOW}3)${NC}   Standard_NC6s_v3          NVIDIA V100    ${RED}16 GB${NC}     6         112 GB  ${RED}(Insufficient)${NC}"
            else
                echo -e "  ${GREEN}1)${NC}   Standard_NV36ads_A10_v5   NVIDIA A10     24 GB     36        440 GB"
                echo -e "  ${GREEN}2)${NC}   Standard_NC24ads_A100_v4  NVIDIA A100    80 GB     24        220 GB"
                echo -e "  ${GREEN}3)${NC}   Standard_NC48ads_A100_v4  NVIDIA A100 x2 160 GB    48        440 GB"
                echo -e "  ${GREEN}4)${NC}   Standard_ND96asr_v4       NVIDIA A100 x8 320 GB    96        900 GB  ${YELLOW}(Premium)${NC}"
            fi
            ;;
        gcp)
            echo -e "  ${BOLD}Region: ${CYAN}$region${NC}"
            echo ""
            printf "  ${BOLD}%-5s %-25s %-15s %-10s %-10s %-10s${NC}\n" "#" "Configuration" "GPU" "VRAM" "vCPUs" "RAM"
            echo -e "  ────────────────────────────────────────────────────────────────────────────"
            
            if [[ "$region" == "asia-south1" ]]; then
                echo -e "  ${GREEN}1)${NC}   n1-standard-16 + L4      NVIDIA L4      24 GB     16        60 GB"
                echo -e "  ${GREEN}2)${NC}   n1-standard-32 + L4 x2   NVIDIA L4 x2   48 GB     32        120 GB"
                echo -e "  ${GREEN}3)${NC}   a2-highgpu-1g            NVIDIA A100    40 GB     12        85 GB"
                echo ""
                echo -e "  ${YELLOW}Note: Limited A100 availability in asia-south1${NC}"
            else
                echo -e "  ${GREEN}1)${NC}   n1-standard-16 + L4      NVIDIA L4      24 GB     16        60 GB"
                echo -e "  ${GREEN}2)${NC}   a2-highgpu-1g            NVIDIA A100    40 GB     12        85 GB"
                echo -e "  ${GREEN}3)${NC}   a2-highgpu-2g            NVIDIA A100 x2 80 GB     24        170 GB"
                echo -e "  ${GREEN}4)${NC}   a2-ultragpu-1g           NVIDIA A100    80 GB     12        170 GB  ${YELLOW}(Premium)${NC}"
            fi
            ;;
        onprem)
            echo -e "  ${BOLD}On-Premise / Sovereign Data Center${NC}"
            echo ""
            echo -e "  For on-premise deployment, ensure your hardware meets:"
            echo ""
            echo -e "  ${GREEN}✓${NC} GPU: NVIDIA A100, A10G, L4, RTX 4090, or A6000"
            echo -e "  ${GREEN}✓${NC} VRAM: 24+ GB recommended (17 GB minimum)"
            echo -e "  ${GREEN}✓${NC} RAM: 64+ GB recommended (32 GB minimum)"
            echo -e "  ${GREEN}✓${NC} Storage: 100+ GB SSD recommended"
            echo -e "  ${GREEN}✓${NC} CUDA: 11.8+ with cuDNN 8.6+"
            ;;
    esac
    echo ""
}

select_template() {
    echo ""
    log "STEP" "Select deployment template"
    
    # Show model requirements first
    show_model_requirements
    show_compatible_gpus
    show_gpu_instance_options "$PLATFORM" "$REGION"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📦 Deployment Templates${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    case "$PLATFORM" in
        aws)
            echo -e "  ${GREEN}1)${NC} ${CYAN}OmniASR Standard${NC} - g5.4xlarge (A10G 24GB)"
            echo -e "     └─ vCPUs: 16 | RAM: 64 GB | Storage: 100 GB"
            echo -e "     └─ Best for: Production ASR workloads"
            echo -e "     └─ Est. Cost: ~\$1.00/hr (ap-south-1)"
            echo ""
            echo -e "  ${GREEN}2)${NC} ${CYAN}OmniASR High Memory${NC} - g5.8xlarge (A10G 24GB)"
            echo -e "     └─ vCPUs: 32 | RAM: 128 GB | Storage: 200 GB"
            echo -e "     └─ Best for: Heavy batch processing"
            echo -e "     └─ Est. Cost: ~\$1.60/hr (ap-south-1)"
            echo ""
            echo -e "  ${GREEN}3)${NC} ${CYAN}OmniASR Multi-GPU${NC} - g5.12xlarge (A10G x4 = 96GB)"
            echo -e "     └─ vCPUs: 48 | RAM: 192 GB | Storage: 500 GB"
            echo -e "     └─ Best for: High-throughput inference"
            echo -e "     └─ Est. Cost: ~\$4.00/hr (ap-south-1)"
            echo ""
            if [[ "$REGION" != "ap-south-1" ]]; then
                echo -e "  ${GREEN}4)${NC} ${CYAN}OmniASR Premium${NC} - p4d.24xlarge (A100 x8 = 320GB)"
                echo -e "     └─ vCPUs: 96 | RAM: 1152 GB | Storage: 1000 GB"
                echo -e "     └─ Best for: Research & large-scale training"
                echo -e "     └─ Est. Cost: ~\$32.00/hr (us-east-1)"
                echo ""
            fi
            echo -e "  ${YELLOW}5)${NC} ${CYAN}Custom${NC} - Configure instance manually"
            echo ""
            ;;
        azure)
            echo -e "  ${GREEN}1)${NC} ${CYAN}OmniASR Standard${NC} - Standard_NV36ads_A10_v5 (A10 24GB)"
            echo -e "     └─ vCPUs: 36 | RAM: 440 GB | Storage: 100 GB"
            echo -e "     └─ Best for: Production ASR workloads"
            echo -e "     └─ Est. Cost: ~\$1.80/hr (centralindia)"
            echo ""
            echo -e "  ${GREEN}2)${NC} ${CYAN}OmniASR Premium${NC} - Standard_NC24ads_A100_v4 (A100 80GB)"
            echo -e "     └─ vCPUs: 24 | RAM: 220 GB | Storage: 200 GB"
            echo -e "     └─ Best for: High-performance inference"
            echo -e "     └─ Est. Cost: ~\$3.70/hr (centralindia)"
            echo ""
            echo -e "  ${GREEN}3)${NC} ${CYAN}OmniASR Multi-GPU${NC} - Standard_NC48ads_A100_v4 (A100 x2)"
            echo -e "     └─ vCPUs: 48 | RAM: 440 GB | Storage: 500 GB"
            echo -e "     └─ Best for: Large batch processing"
            echo -e "     └─ Est. Cost: ~\$7.40/hr"
            echo ""
            echo -e "  ${YELLOW}4)${NC} ${CYAN}Custom${NC} - Configure instance manually"
            echo ""
            ;;
        gcp)
            echo -e "  ${GREEN}1)${NC} ${CYAN}OmniASR Standard${NC} - n1-standard-16 + L4 (24GB)"
            echo -e "     └─ vCPUs: 16 | RAM: 60 GB | Storage: 100 GB"
            echo -e "     └─ Best for: Production ASR workloads"
            echo -e "     └─ Est. Cost: ~\$0.80/hr (asia-south1)"
            echo ""
            echo -e "  ${GREEN}2)${NC} ${CYAN}OmniASR Premium${NC} - a2-highgpu-1g (A100 40GB)"
            echo -e "     └─ vCPUs: 12 | RAM: 85 GB | Storage: 200 GB"
            echo -e "     └─ Best for: High-performance inference"
            echo -e "     └─ Est. Cost: ~\$3.50/hr (asia-south1)"
            echo ""
            echo -e "  ${GREEN}3)${NC} ${CYAN}OmniASR Ultra${NC} - a2-ultragpu-1g (A100 80GB)"
            echo -e "     └─ vCPUs: 12 | RAM: 170 GB | Storage: 500 GB"
            echo -e "     └─ Best for: Research & development"
            echo -e "     └─ Est. Cost: ~\$5.00/hr"
            echo ""
            echo -e "  ${YELLOW}4)${NC} ${CYAN}Custom${NC} - Configure instance manually"
            echo ""
            ;;
        onprem)
            echo -e "  ${GREEN}1)${NC} ${CYAN}Standard Setup${NC} - Single GPU deployment"
            echo -e "     └─ Minimum: 1x GPU (24GB VRAM), 32GB RAM, 50GB Storage"
            echo ""
            echo -e "  ${GREEN}2)${NC} ${CYAN}High Availability${NC} - Multi-node with load balancing"
            echo -e "     └─ Recommended: 2+ nodes, each with GPU"
            echo ""
            echo -e "  ${YELLOW}3)${NC} ${CYAN}Custom${NC} - Configure deployment manually"
            echo ""
            ;;
    esac
    
    # Get max options based on platform and region
    local max_options=5
    case "$PLATFORM" in
        aws)
            if [[ "$REGION" == "ap-south-1" ]]; then
                max_options=5  # No p4d in India
            else
                max_options=5
            fi
            ;;
        azure|gcp)
            max_options=4
            ;;
        onprem)
            max_options=3
            ;;
    esac
    
    while true; do
        read -p "Enter your choice (1-$max_options) [1]: " choice
        choice=${choice:-1}
        
        case "$PLATFORM" in
            aws)
                case "$choice" in
                    1) 
                        TEMPLATE="omniasr-standard"
                        INSTANCE_TYPE="g5.4xlarge"
                        VOLUME_SIZE=100
                        break ;;
                    2) 
                        TEMPLATE="omniasr-highmem"
                        INSTANCE_TYPE="g5.8xlarge"
                        VOLUME_SIZE=200
                        break ;;
                    3) 
                        TEMPLATE="omniasr-multigpu"
                        INSTANCE_TYPE="g5.12xlarge"
                        VOLUME_SIZE=500
                        break ;;
                    4)
                        if [[ "$REGION" != "ap-south-1" ]]; then
                            TEMPLATE="omniasr-premium"
                            INSTANCE_TYPE="p4d.24xlarge"
                            VOLUME_SIZE=1000
                            break
                        else
                            TEMPLATE="custom"
                            configure_custom_instance
                            break
                        fi
                        ;;
                    5) 
                        TEMPLATE="custom"
                        configure_custom_instance
                        break ;;
                    *) echo -e "${RED}Invalid choice. Please enter 1-$max_options.${NC}" ;;
                esac
                ;;
            azure)
                case "$choice" in
                    1) 
                        TEMPLATE="omniasr-standard"
                        INSTANCE_TYPE="Standard_NV36ads_A10_v5"
                        VOLUME_SIZE=100
                        break ;;
                    2) 
                        TEMPLATE="omniasr-premium"
                        INSTANCE_TYPE="Standard_NC24ads_A100_v4"
                        VOLUME_SIZE=200
                        break ;;
                    3) 
                        TEMPLATE="omniasr-multigpu"
                        INSTANCE_TYPE="Standard_NC48ads_A100_v4"
                        VOLUME_SIZE=500
                        break ;;
                    4) 
                        TEMPLATE="custom"
                        configure_custom_instance
                        break ;;
                    *) echo -e "${RED}Invalid choice. Please enter 1-4.${NC}" ;;
                esac
                ;;
            gcp)
                case "$choice" in
                    1) 
                        TEMPLATE="omniasr-standard"
                        MACHINE_TYPE="n1-standard-16"
                        GPU_TYPE="nvidia-l4"
                        GPU_COUNT=1
                        VOLUME_SIZE=100
                        break ;;
                    2) 
                        TEMPLATE="omniasr-premium"
                        MACHINE_TYPE="a2-highgpu-1g"
                        GPU_TYPE="nvidia-tesla-a100"
                        GPU_COUNT=1
                        VOLUME_SIZE=200
                        break ;;
                    3) 
                        TEMPLATE="omniasr-ultra"
                        MACHINE_TYPE="a2-ultragpu-1g"
                        GPU_TYPE="nvidia-tesla-a100"
                        GPU_COUNT=1
                        VOLUME_SIZE=500
                        break ;;
                    4) 
                        TEMPLATE="custom"
                        configure_custom_instance
                        break ;;
                    *) echo -e "${RED}Invalid choice. Please enter 1-4.${NC}" ;;
                esac
                ;;
            onprem)
                case "$choice" in
                    1) TEMPLATE="onprem-standard"; break ;;
                    2) TEMPLATE="onprem-ha"; break ;;
                    3) TEMPLATE="custom"; break ;;
                    *) echo -e "${RED}Invalid choice. Please enter 1-3.${NC}" ;;
                esac
                ;;
        esac
    done
    
    log "SUCCESS" "Selected template: $TEMPLATE"
    
    # Show selection summary
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ✓ Configuration Summary${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Template:  ${GREEN}$TEMPLATE${NC}"
    case "$PLATFORM" in
        aws)
            echo -e "  Instance:  ${GREEN}$INSTANCE_TYPE${NC}"
            echo -e "  Storage:   ${GREEN}${VOLUME_SIZE} GB${NC}"
            ;;
        azure)
            echo -e "  Instance:  ${GREEN}$INSTANCE_TYPE${NC}"
            echo -e "  Storage:   ${GREEN}${VOLUME_SIZE} GB${NC}"
            ;;
        gcp)
            echo -e "  Machine:   ${GREEN}$MACHINE_TYPE${NC}"
            echo -e "  GPU:       ${GREEN}$GPU_TYPE x $GPU_COUNT${NC}"
            echo -e "  Storage:   ${GREEN}${VOLUME_SIZE} GB${NC}"
            ;;
    esac
    echo ""
}

configure_custom_instance() {
    echo ""
    echo -e "${BOLD}Custom Instance Configuration${NC}"
    echo ""
    
    case "$PLATFORM" in
        aws)
            echo -e "Available AWS GPU instance types:"
            echo -e "  g5.xlarge, g5.2xlarge, g5.4xlarge, g5.8xlarge, g5.12xlarge, g5.16xlarge"
            echo -e "  p3.2xlarge, p3.8xlarge, p3.16xlarge (V100 - limited VRAM)"
            echo -e "  p4d.24xlarge (A100 - US regions only)"
            echo ""
            read -p "Enter instance type [g5.4xlarge]: " INSTANCE_TYPE
            INSTANCE_TYPE=${INSTANCE_TYPE:-g5.4xlarge}
            ;;
        azure)
            echo -e "Available Azure GPU instance types:"
            echo -e "  Standard_NV36ads_A10_v5 (A10)"
            echo -e "  Standard_NC24ads_A100_v4, Standard_NC48ads_A100_v4 (A100)"
            echo -e "  Standard_NC6s_v3, Standard_NC12s_v3 (V100 - limited VRAM)"
            echo ""
            read -p "Enter instance type [Standard_NV36ads_A10_v5]: " INSTANCE_TYPE
            INSTANCE_TYPE=${INSTANCE_TYPE:-Standard_NV36ads_A10_v5}
            ;;
        gcp)
            echo -e "Available GCP machine types with GPUs:"
            echo -e "  n1-standard-8/16/32 with nvidia-l4 or nvidia-tesla-t4"
            echo -e "  a2-highgpu-1g/2g/4g/8g (with A100)"
            echo -e "  a2-ultragpu-1g (with A100 80GB)"
            echo ""
            read -p "Enter machine type [n1-standard-16]: " MACHINE_TYPE
            MACHINE_TYPE=${MACHINE_TYPE:-n1-standard-16}
            read -p "Enter GPU type [nvidia-l4]: " GPU_TYPE
            GPU_TYPE=${GPU_TYPE:-nvidia-l4}
            read -p "Enter GPU count [1]: " GPU_COUNT
            GPU_COUNT=${GPU_COUNT:-1}
            ;;
    esac
    
    read -p "Enter storage size in GB [100]: " VOLUME_SIZE
    VOLUME_SIZE=${VOLUME_SIZE:-100}
}

# ==============================================================================
# Credential Configuration
# ==============================================================================

configure_credentials() {
    local provider="$1"
    
    echo ""
    log "STEP" "Configure credentials for $(get_platform_name $provider)"
    echo ""
    
    case "$provider" in
        aws)
            configure_aws_credentials
            ;;
        azure)
            configure_azure_credentials
            ;;
        gcp)
            configure_gcp_credentials
            ;;
        onprem)
            configure_onprem_credentials
            ;;
    esac
}

configure_aws_credentials() {
    echo -e "${BOLD}AWS Authentication${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Enter your AWS Access Keys to deploy the infrastructure.${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Access Keys look like this:"
    echo "    • Access Key ID:     AKIAIOSFODNN7EXAMPLE"
    echo "    • Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    echo ""
    echo "  1) Enter Access Keys"
    echo "  2) I don't have Access Keys - help me get them"
    echo ""
    
    while true; do
        read -p "  Enter your choice (1-2): " key_choice
        case "$key_choice" in
            1)
                # User has keys - get them directly
                echo ""
                read -p "  Access Key ID: " AWS_ACCESS_KEY
                read -sp "  Secret Access Key: " AWS_SECRET_KEY
                echo ""
                
                if [[ -z "$AWS_ACCESS_KEY" || -z "$AWS_SECRET_KEY" ]]; then
                    log "ERROR" "Both Access Key ID and Secret Access Key are required"
                    continue
                fi
                
                validate_aws_credentials
                break
                ;;
            2)
                # Guide user to create keys
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
    echo -e "  ${BOLD}Option 1: Create them yourself (if you have permission)${NC}"
    echo ""
    echo -e "  ${GREEN}Step 1:${NC} Login to AWS Console"
    echo -e "  ${GREEN}Step 2:${NC} Click your ${BOLD}username${NC} (top-right corner)"
    echo -e "  ${GREEN}Step 3:${NC} Click ${BOLD}\"Security credentials\"${NC}"
    echo -e "  ${GREEN}Step 4:${NC} Scroll to ${BOLD}\"Access keys\"${NC} section"
    echo -e "  ${GREEN}Step 5:${NC} Click ${BOLD}\"Create access key\"${NC}"
    echo -e "  ${GREEN}Step 6:${NC} Select ${BOLD}\"Command Line Interface (CLI)\"${NC}"
    echo -e "  ${GREEN}Step 7:${NC} Copy both keys and save them securely!"
    echo ""
    echo -e "  ${BOLD}Option 2: Request from your AWS administrator${NC}"
    echo ""
    echo -e "  Send them this message:"
    echo ""
    echo -e "${CYAN}  ───────────────────────────────────────────────────────────${NC}"
    echo "  Hi, I need AWS Access Keys for deploying GPU infrastructure."
    echo ""
    echo "  Please either:"
    echo "  1. Create Access Keys for my IAM user and share securely, OR"
    echo "  2. Grant me 'iam:CreateAccessKey' permission"
    echo ""
    echo "  Required permissions for deployment:"
    echo "  • EC2 (full) - GPU instances, VPC, networking"
    echo "  • Auto Scaling, Lambda, EventBridge, CloudWatch Logs"
    echo "  • IAM (create roles for Lambda)"
    echo -e "${CYAN}  ───────────────────────────────────────────────────────────${NC}"
    echo ""
    
    echo -e "  Press ${GREEN}ENTER${NC} to open AWS Console..."
    read -r
    
    # Open browser
    local login_url="https://console.aws.amazon.com/"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$login_url" 2>/dev/null
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$login_url" 2>/dev/null
    fi
    
    echo ""
    echo -e "  ${BOLD}Once you have your Access Keys, enter them below:${NC}"
    echo ""
    
    read -p "  Access Key ID: " AWS_ACCESS_KEY
    
    if [[ -z "$AWS_ACCESS_KEY" ]]; then
        log "ERROR" "Access Key ID is required. Please contact your AWS administrator."
        exit 1
    fi
    
    read -sp "  Secret Access Key: " AWS_SECRET_KEY
    echo ""
    
    if [[ -z "$AWS_SECRET_KEY" ]]; then
        log "ERROR" "Secret Access Key is required."
        exit 1
    fi
    
    validate_aws_credentials
}

validate_aws_credentials() {
    echo ""
    log "INFO" "Validating AWS credentials..."
    
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"
    
    if aws sts get-caller-identity --region "${REGION:-ap-south-1}" &> /dev/null; then
        log "SUCCESS" "AWS credentials validated successfully!"
        
        # Get account info
        local caller_info=$(aws sts get-caller-identity --output json 2>/dev/null)
        local verified_account=$(echo "$caller_info" | jq -r '.Account' 2>/dev/null)
        local verified_arn=$(echo "$caller_info" | jq -r '.Arn' 2>/dev/null)
        
        echo ""
        echo -e "  ${GREEN}✓${NC} Account: $verified_account"
        echo -e "  ${GREEN}✓${NC} User:    $verified_arn"
        
    else
        log "ERROR" "AWS credential validation failed"
        echo ""
        echo -e "${RED}  The credentials didn't work. This could mean:${NC}"
        echo "  • The Access Key ID or Secret Key was typed incorrectly"
        echo "  • The keys were deleted or deactivated"
        echo "  • Copy/paste error (extra spaces?)"
        echo ""
        
        if confirm "  Would you like to try entering the keys again?"; then
            get_access_keys_from_user
        else
            exit 1
        fi
    fi
}

configure_azure_credentials() {
    echo -e "${BOLD}Azure Authentication${NC}"
    echo ""
    echo -e "${CYAN}Enter your Azure credentials:${NC}"
    echo ""
    echo -e "${YELLOW}How to get Azure credentials:${NC}"
    echo "1. Login to Azure Portal: https://portal.azure.com"
    echo "2. Go to: Azure Active Directory → App registrations → New registration"
    echo "3. Or use Azure CLI: az ad sp create-for-rbac --name 'terraform-sp' --role Contributor"
    echo ""
    
    # Ask for all required credentials
    read -p "Subscription ID (from Azure Portal → Subscriptions): " AZURE_SUBSCRIPTION_ID
    read -p "Tenant ID / Directory ID: " AZURE_TENANT_ID
    read -p "Client ID / Application ID: " AZURE_CLIENT_ID
    read -sp "Client Secret / Password: " AZURE_CLIENT_SECRET
    echo ""
    
    if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_TENANT_ID" || -z "$AZURE_CLIENT_ID" || -z "$AZURE_CLIENT_SECRET" ]]; then
        log "ERROR" "All Azure credentials are required"
        exit 1
    fi
    
    AUTH_METHOD="sp"
    
    # Validate credentials
    echo ""
    log "INFO" "Validating Azure credentials..."
    
    export ARM_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
    export ARM_TENANT_ID="$AZURE_TENANT_ID"
    export ARM_CLIENT_ID="$AZURE_CLIENT_ID"
    export ARM_CLIENT_SECRET="$AZURE_CLIENT_SECRET"
    
    if command -v az &> /dev/null; then
        if az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" &> /dev/null; then
            log "SUCCESS" "Azure credentials validated successfully"
            
            # Show subscription info
            local sub_name=$(az account show --query name -o tsv 2>/dev/null)
            echo -e "  Subscription: ${GREEN}$sub_name${NC}"
        else
            log "WARN" "Could not validate Azure credentials via CLI"
        fi
    else
        log "INFO" "Azure CLI not installed - credentials will be validated during deployment"
    fi
}

configure_gcp_credentials() {
    echo -e "${BOLD}GCP Authentication${NC}"
    echo ""
    echo -e "${CYAN}Enter your GCP credentials:${NC}"
    echo ""
    echo -e "${YELLOW}How to get GCP credentials:${NC}"
    echo "1. Go to GCP Console: https://console.cloud.google.com"
    echo "2. Go to: IAM & Admin → Service Accounts"
    echo "3. Create Service Account with roles: Compute Admin, IAM Admin"
    echo "4. Create and download JSON key file"
    echo ""
    
    read -p "GCP Project ID: " GCP_PROJECT_ID
    read -p "Path to Service Account JSON key file: " GCP_CREDENTIALS_FILE
    
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        log "ERROR" "GCP Project ID is required"
        exit 1
    fi
    
    if [[ -n "$GCP_CREDENTIALS_FILE" ]]; then
        if [[ ! -f "$GCP_CREDENTIALS_FILE" ]]; then
            log "ERROR" "Service Account JSON file not found: $GCP_CREDENTIALS_FILE"
            exit 1
        fi
        AUTH_METHOD="file"
        
        # Validate JSON file
        if ! jq -e '.type == "service_account"' "$GCP_CREDENTIALS_FILE" &> /dev/null; then
            log "WARN" "File may not be a valid Service Account JSON"
        fi
        
        # Extract service account email
        local sa_email=$(jq -r '.client_email' "$GCP_CREDENTIALS_FILE" 2>/dev/null)
        if [[ -n "$sa_email" ]]; then
            echo -e "  Service Account: ${GREEN}$sa_email${NC}"
        fi
    else
        log "INFO" "No credentials file provided - will use Application Default Credentials"
        GCP_USE_ADC="true"
        AUTH_METHOD="adc"
    fi
    
    # Validate credentials
    echo ""
    log "INFO" "Validating GCP credentials..."
    
    if [[ -n "$GCP_CREDENTIALS_FILE" ]]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDENTIALS_FILE"
    fi
    export GOOGLE_PROJECT="$GCP_PROJECT_ID"
    
    if command -v gcloud &> /dev/null; then
        if [[ -n "$GCP_CREDENTIALS_FILE" ]]; then
            if gcloud auth activate-service-account --key-file="$GCP_CREDENTIALS_FILE" &> /dev/null; then
                log "SUCCESS" "GCP credentials validated successfully"
            else
                log "WARN" "Could not validate GCP credentials"
            fi
        fi
        
        # Check project access
        if gcloud projects describe "$GCP_PROJECT_ID" &> /dev/null; then
            log "SUCCESS" "Project access verified: $GCP_PROJECT_ID"
        else
            log "WARN" "Could not verify access to project: $GCP_PROJECT_ID"
        fi
    else
        log "INFO" "GCP CLI not installed - credentials will be validated during deployment"
    fi
}

configure_onprem_credentials() {
    echo -e "${BOLD}On-Premise Configuration${NC}"
    echo ""
    echo -e "${YELLOW}Note: On-premise deployment requires additional setup.${NC}"
    echo ""
    
    read -p "Target server hostname/IP: " ONPREM_HOST
    read -p "SSH Username: " ONPREM_USER
    read -p "SSH Key path [~/.ssh/id_rsa]: " ONPREM_SSH_KEY
    ONPREM_SSH_KEY=${ONPREM_SSH_KEY:-~/.ssh/id_rsa}
    
    # Validate SSH connection
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$ONPREM_SSH_KEY" "${ONPREM_USER}@${ONPREM_HOST}" "echo 'connected'" &> /dev/null; then
        log "SUCCESS" "SSH connection verified"
    else
        log "WARN" "Could not verify SSH connection. Please check credentials."
    fi
}

# ==============================================================================
# Configuration Generation
# ==============================================================================

generate_config() {
    local provider="$1"
    local template="$2"
    
    log "STEP" "Generating configuration..."
    
    # Start with example and modify
    cp "${SCRIPT_DIR}/terraform.tfvars.example" "$CONFIG_FILE"
    
    # Common settings
    cat > "$CONFIG_FILE" << EOF
# ==============================================================================
# DPG Infrastructure Configuration
# Generated by deploy.sh on $(date)
# Template: $template
# ==============================================================================

# General Configuration
project_name = "${PROJECT_NAME:-dpg-infra}"
environment  = "${ENVIRONMENT:-dev}"
owner        = "${OWNER:-DPG Deployment}"

# Cloud Provider
cloud_provider = "$provider"

# Region Preference
preferred_region      = "${PREFERRED_REGION:-india}"
auto_fallback_to_us   = true
skip_instance_check   = false

EOF

    # Provider-specific configuration
    case "$provider" in
        aws)
            cat >> "$CONFIG_FILE" << EOF
# AWS Configuration
aws_region             = "${REGION:-ap-south-1}"
aws_availability_zones = ["${REGION:-ap-south-1}a", "${REGION:-ap-south-1}b"]
EOF
            if [[ "${AUTH_METHOD:-}" == "profile" ]]; then
                echo "aws_profile = \"${AWS_PROFILE}\"" >> "$CONFIG_FILE"
            elif [[ "${AUTH_METHOD:-}" == "keys" ]]; then
                echo "aws_account_id   = \"${AWS_ACCOUNT_ID}\"" >> "$CONFIG_FILE"
                echo "aws_iam_username = \"${AWS_IAM_USERNAME}\"" >> "$CONFIG_FILE"
                echo "aws_access_key   = \"${AWS_ACCESS_KEY}\"" >> "$CONFIG_FILE"
                echo "aws_secret_key   = \"${AWS_SECRET_KEY}\"" >> "$CONFIG_FILE"
            fi
            ;;
        azure)
            cat >> "$CONFIG_FILE" << EOF
# Azure Configuration
azure_location        = "${REGION:-centralindia}"
azure_subscription_id = "${AZURE_SUBSCRIPTION_ID:-}"
azure_tenant_id       = "${AZURE_TENANT_ID:-}"
azure_client_id       = "${AZURE_CLIENT_ID:-}"
azure_client_secret   = "${AZURE_CLIENT_SECRET:-}"
azure_use_cli         = ${AZURE_USE_CLI:-false}
EOF
            ;;
        gcp)
            cat >> "$CONFIG_FILE" << EOF
# GCP Configuration
gcp_project_id       = "${GCP_PROJECT_ID:-}"
gcp_region           = "${REGION:-asia-south1}"
gcp_zone             = "${REGION:-asia-south1}-a"
gcp_credentials_file = "${GCP_CREDENTIALS_FILE:-}"
gcp_use_adc          = ${GCP_USE_ADC:-false}
EOF
            ;;
    esac
    
    # Template-specific settings
    case "$template" in
        minimal)
            cat >> "$CONFIG_FILE" << EOF

# Minimal Template Settings
asg_min_size         = 1
asg_max_size         = 1
asg_desired_capacity = 1
enable_load_balancer = false
enable_scheduling    = false
EOF
            ;;
        standard)
            cat >> "$CONFIG_FILE" << EOF

# Standard Template Settings
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 1
enable_load_balancer = true
enable_scheduling    = true
schedule_start_cron  = "cron(0 4 ? * MON-FRI *)"
schedule_stop_cron   = "cron(0 15 ? * MON-FRI *)"
EOF
            ;;
        production)
            cat >> "$CONFIG_FILE" << EOF

# Production Template Settings
asg_min_size         = 2
asg_max_size         = 10
asg_desired_capacity = 2
enable_load_balancer = true
enable_scheduling    = false  # Always on for production

# Enhanced monitoring
health_check_interval = 15
healthy_threshold     = 2
unhealthy_threshold   = 2
EOF
            ;;
        development)
            cat >> "$CONFIG_FILE" << EOF

# Development Template Settings
asg_min_size         = 0
asg_max_size         = 1
asg_desired_capacity = 1
enable_load_balancer = false
enable_scheduling    = true
schedule_start_cron  = "cron(0 4 ? * MON-FRI *)"
schedule_stop_cron   = "cron(0 12 ? * MON-FRI *)"  # Shorter hours for dev
EOF
            ;;
    esac
    
    log "SUCCESS" "Configuration generated: $CONFIG_FILE"
}

# ==============================================================================
# Check Existing Instances
# ==============================================================================

check_existing_instances() {
    local provider="$1"
    
    log "STEP" "Checking for existing instances..."
    
    case "$provider" in
        aws)
            if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
                local instances=$(aws ec2 describe-instances \
                    --filters "Name=tag:Project,Values=${PROJECT_NAME:-dpg-infra}" \
                              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
                    --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}' \
                    --output table 2>/dev/null || echo "")
                
                if [[ -n "$instances" && ! "$instances" =~ "None" ]]; then
                    echo ""
                    log "WARN" "Existing instances found:"
                    echo "$instances"
                    echo ""
                    if ! confirm "Do you want to continue and manage these with Terraform?"; then
                        log "INFO" "Deployment cancelled by user"
                        exit 0
                    fi
                else
                    log "SUCCESS" "No existing instances found"
                fi
            fi
            ;;
        azure)
            if command -v az &> /dev/null && az account show &> /dev/null; then
                local vms=$(az vm list \
                    --query "[?tags.Project=='${PROJECT_NAME:-dpg-infra}'].{Name:name,State:powerState,Size:hardwareProfile.vmSize}" \
                    --output table 2>/dev/null || echo "")
                
                if [[ -n "$vms" && ! "$vms" =~ "Name" ]]; then
                    echo ""
                    log "WARN" "Existing VMs found:"
                    echo "$vms"
                    echo ""
                    if ! confirm "Do you want to continue?"; then
                        log "INFO" "Deployment cancelled by user"
                        exit 0
                    fi
                else
                    log "SUCCESS" "No existing VMs found"
                fi
            fi
            ;;
        gcp)
            if command -v gcloud &> /dev/null; then
                local instances=$(gcloud compute instances list \
                    --filter="labels.project=${PROJECT_NAME:-dpg-infra}" \
                    --format="table(name,zone,status,machineType)" 2>/dev/null || echo "")
                
                if [[ -n "$instances" && "$instances" =~ "NAME" ]]; then
                    echo ""
                    log "WARN" "Existing instances found:"
                    echo "$instances"
                    echo ""
                    if ! confirm "Do you want to continue?"; then
                        log "INFO" "Deployment cancelled by user"
                        exit 0
                    fi
                else
                    log "SUCCESS" "No existing instances found"
                fi
            fi
            ;;
    esac
}

# ==============================================================================
# Terraform Operations
# ==============================================================================

terraform_init() {
    log "STEP" "Initializing Terraform..."
    
    cd "$SCRIPT_DIR"
    
    if terraform init -input=false 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Terraform initialized"
        return 0
    else
        log "ERROR" "Terraform initialization failed"
        return 1
    fi
}

terraform_validate() {
    log "STEP" "Validating configuration..."
    
    cd "$SCRIPT_DIR"
    
    if terraform validate 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Configuration is valid"
        return 0
    else
        log "ERROR" "Configuration validation failed"
        return 1
    fi
}

terraform_plan() {
    log "STEP" "Creating deployment plan..."
    
    cd "$SCRIPT_DIR"
    
    if terraform plan -input=false -out=tfplan 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Deployment plan created"
        return 0
    else
        log "ERROR" "Plan creation failed"
        return 1
    fi
}

terraform_apply() {
    log "STEP" "Deploying infrastructure..."
    
    cd "$SCRIPT_DIR"
    
    echo ""
    echo -e "${YELLOW}This will create cloud resources that may incur costs.${NC}"
    
    if ! confirm "Do you want to proceed with the deployment?" "N"; then
        log "INFO" "Deployment cancelled by user"
        return 1
    fi
    
    echo ""
    log "INFO" "Deployment in progress. This may take 5-15 minutes..."
    echo ""
    
    if terraform apply -input=false -auto-approve tfplan 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Infrastructure deployed successfully!"
        save_state "deployed"
        return 0
    else
        log "ERROR" "Deployment failed"
        save_state "failed"
        return 1
    fi
}

terraform_destroy() {
    log "STEP" "Destroying infrastructure..."
    
    cd "$SCRIPT_DIR"
    
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

# ==============================================================================
# Output & Status
# ==============================================================================

show_outputs() {
    log "STEP" "Deployment Outputs"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    terraform output 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Check the outputs above for connection details"
    echo "  2. Review the deployment in your cloud console"
    echo "  3. Test the application endpoint"
    echo ""
    echo "Useful commands:"
    echo "  ./deploy.sh --status   - Check deployment status"
    echo "  ./deploy.sh --destroy  - Tear down infrastructure"
    echo ""
}

show_status() {
    echo ""
    log "STEP" "Deployment Status"
    echo ""
    
    local state=$(get_state)
    echo "Current state: $state"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    if [[ -f "${SCRIPT_DIR}/.terraform/terraform.tfstate" ]] || [[ -f "${SCRIPT_DIR}/terraform.tfstate" ]]; then
        terraform show -no-color 2>/dev/null | head -50 || true
    else
        echo "No Terraform state found."
    fi
}

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
    
    read -p "Environment (dev/staging/prod) [dev]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-dev}
    
    read -p "Owner/Organization [DPG Deployment]: " OWNER
    OWNER=${OWNER:-DPG Deployment}
    
    # Step 3: Platform selection
    select_platform
    
    # Step 4: Region selection
    select_region "$PLATFORM"
    
    # Step 5: Template selection
    select_template
    
    # Step 6: Configure credentials (always prompt for new deployment)
    configure_credentials "$PLATFORM"
    
    # Step 7: Validate credentials work
    if [[ "$PLATFORM" != "onprem" ]]; then
        if ! validate_cloud_credentials "$PLATFORM"; then
            log "ERROR" "Credential validation failed"
            exit 1
        fi
    fi
    
    # Step 8: Check existing instances
    if [[ "$PLATFORM" != "onprem" && "$PLATFORM" != "ati" ]]; then
        check_existing_instances "$PLATFORM"
    fi
    
    # Step 9: Generate configuration
    generate_config "$PLATFORM" "$TEMPLATE"
    
    # Step 10: Terraform operations
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
    
    # Step 11: Apply
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
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "No configuration file found: $CONFIG_FILE"
        log "INFO" "Run without --auto for interactive setup, or create terraform.tfvars first"
        exit 1
    fi
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    terraform_init || exit 1
    terraform_validate || exit 1
    terraform_plan || exit 1
    
    # In auto mode, apply without confirmation
    cd "$SCRIPT_DIR"
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
    
    # Execute based on mode
    if [[ "$STATUS_MODE" == true ]]; then
        show_status
    elif [[ "$DESTROY_MODE" == true ]]; then
        print_banner
        terraform_destroy
    elif [[ "$VALIDATE_MODE" == true ]]; then
        print_banner
        check_prerequisites || exit 1
        terraform_init || exit 1
        terraform_validate
    elif [[ "$PLAN_MODE" == true ]]; then
        print_banner
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
