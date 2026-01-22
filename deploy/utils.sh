#!/bin/bash
# ==============================================================================
# DPG Deployment - Utility Functions
# ==============================================================================
# Main entry point that sources modular utility files.
# ==============================================================================

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Source Modular Components
# ==============================================================================

# Logging utilities
source "${DEPLOY_DIR}/utils_logging.sh"

# UI utilities (banner, help, prompts)
source "${DEPLOY_DIR}/utils_ui.sh"

# Progress bar utilities
source "${DEPLOY_DIR}/utils_progress.sh"

# State management utilities
source "${DEPLOY_DIR}/utils_state.sh"
