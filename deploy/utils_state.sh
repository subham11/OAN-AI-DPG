#!/bin/bash
# ==============================================================================
# DPG Deployment - State Management Utilities
# ==============================================================================
# Functions for deployment state management and status display.
# ==============================================================================

# ==============================================================================
# State Management
# ==============================================================================

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
# Status Display
# ==============================================================================

show_status() {
    print_banner
    
    echo -e "${BOLD}Deployment Status${NC}"
    echo ""
    
    local state=$(get_state)
    case "$state" in
        "deployed")
            echo -e "  Status: ${GREEN}Deployed${NC}"
            ;;
        "failed")
            echo -e "  Status: ${RED}Failed${NC}"
            ;;
        "destroyed")
            echo -e "  Status: ${YELLOW}Destroyed${NC}"
            ;;
        *)
            echo -e "  Status: ${BLUE}Not Deployed${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}Available Environments:${NC}"
    echo ""
    
    for provider in aws azure gcp; do
        if [[ -d "${SCRIPT_DIR}/environments/${provider}" ]]; then
            echo -e "  ${CYAN}${provider}:${NC}"
            for env in "${SCRIPT_DIR}/environments/${provider}"/*; do
                if [[ -d "$env" ]]; then
                    local env_name=$(basename "$env")
                    local has_state=""
                    if [[ -d "${env}/.terraform" ]]; then
                        has_state=" ${GREEN}(initialized)${NC}"
                    fi
                    echo -e "    - ${env_name}${has_state}"
                fi
            done
        fi
    done
    
    echo ""
}
