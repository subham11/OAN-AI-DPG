#!/bin/bash
# ==============================================================================
# DPG Deployment - UI Utilities
# ==============================================================================
# Functions for banners, help display, and general UI elements.
# ==============================================================================

# ==============================================================================
# Banner
# ==============================================================================

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
║                          Version 2.0.0                                    ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ==============================================================================
# Help Display
# ==============================================================================

print_help() {
    cat << EOF
DPG Single-Click Deployment Script v${VERSION}

Usage: ./deploy.sh [OPTIONS]

Options:
  --auto                 Run in automated mode using existing config
  --platform, -p NAME    Cloud platform (aws, azure, gcp)
  --environment, -e NAME Environment (dev, staging, prod) [default: staging]
  --template NAME        Use a pre-configured template
  --destroy              Destroy existing infrastructure
  --status               Show current deployment status
  --validate             Validate configuration without deploying
  --plan                 Show deployment plan without applying
  --check-permissions    Check AWS IAM permissions before deployment
  --help                 Show this help message

Examples:
  ./deploy.sh                                      Interactive wizard
  ./deploy.sh -p aws -e staging --auto             Automated AWS deploy
  ./deploy.sh -p aws -e staging --plan             Plan only
  ./deploy.sh -p azure -e prod --destroy           Destroy Azure prod
  ./deploy.sh --check-permissions                  Check AWS permissions
  ./deploy.sh --status

Directory Structure:
  environments/
    aws/staging/      - AWS staging configuration
    azure/staging/    - Azure staging configuration
    gcp/staging/      - GCP staging configuration

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

# ==============================================================================
# Spinner
# ==============================================================================

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

# ==============================================================================
# Prompt Functions
# ==============================================================================

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
