#!/bin/bash
# ==============================================================================
# DPG Deployment - Configuration & Constants
# ==============================================================================
# This file contains all configuration variables, constants, and helper
# functions for platform/region/template lookups.
# ==============================================================================

# Version
VERSION="2.0.0"

# Directory paths (set by main script)
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Environment directory (set dynamically based on provider and environment)
ENV_DIR=""
CONFIG_FILE=""

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

# ==============================================================================
# Environment Directory Functions
# ==============================================================================

# Get the environment directory for a given provider and environment
get_env_dir() {
    local provider="$1"
    local environment="${2:-staging}"
    echo "${SCRIPT_DIR}/environments/${provider}/${environment}"
}

# Set the working directory based on provider and environment
set_working_directory() {
    local provider="$1"
    local environment="${2:-staging}"
    
    ENV_DIR=$(get_env_dir "$provider" "$environment")
    CONFIG_FILE="${ENV_DIR}/terraform.tfvars"
    
    if [[ ! -d "$ENV_DIR" ]]; then
        log "ERROR" "Environment directory not found: $ENV_DIR"
        echo ""
        echo "Available environments:"
        ls -la "${SCRIPT_DIR}/environments/${provider}/" 2>/dev/null || echo "  No environments found for $provider"
        return 1
    fi
    
    log "INFO" "Using environment directory: $ENV_DIR"
    return 0
}

# ==============================================================================
# Platform Helpers
# ==============================================================================

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

# ==============================================================================
# Template Helpers
# ==============================================================================

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
# GPU Instance Configurations
# ==============================================================================

# Get GPU instances for each provider
get_gpu_instances_aws() {
    cat << 'EOF'
g4dn.xlarge:T4 16GB:4:16:$0.526:Development/Testing
g4dn.2xlarge:T4 16GB:8:32:$0.752:Standard Workloads
g4dn.4xlarge:T4 16GB:16:64:$1.204:Memory Intensive
g5.xlarge:A10G 24GB:4:16:$1.006:ML Training
g5.2xlarge:A10G 24GB:8:32:$1.212:Production ML
p4d.24xlarge:A100 40GB×8:96:1152:$32.77:Heavy Training
EOF
}

get_gpu_instances_azure() {
    cat << 'EOF'
Standard_NC4as_T4_v3:T4 16GB:4:28:$0.526:Development
Standard_NC8as_T4_v3:T4 16GB:8:56:$0.752:Standard
Standard_NC16as_T4_v3:T4 16GB:16:110:$1.204:Production
Standard_NC24ads_A100_v4:A100 80GB:24:220:$3.67:Heavy Training
EOF
}

get_gpu_instances_gcp() {
    cat << 'EOF'
n1-standard-4+T4:T4 16GB:4:15:$0.55:Development
n1-standard-8+T4:T4 16GB:8:30:$0.75:Standard
n1-highmem-8+T4:T4 16GB:8:52:$0.85:Memory Intensive
a2-highgpu-1g:A100 40GB:12:85:$3.67:Heavy Training
EOF
}
