#!/bin/bash
# ==============================================================================
# DPG Deployment - Logging Utilities
# ==============================================================================
# Functions for logging messages to console and log file.
# ==============================================================================

# ==============================================================================
# Logging Functions
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
