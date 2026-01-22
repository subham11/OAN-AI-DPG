#!/bin/bash
# ==============================================================================
# DPG Deployment - Interactive Selection Prompts
# ==============================================================================
# Functions for platform, region, template, and instance selection.
# ==============================================================================

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
    echo "    1) AWS    - Amazon Web Services (Default: us-east-1)"
    echo "    2) Azure  - Microsoft Azure (Default: eastus)"  
    echo "    3) GCP    - Google Cloud Platform (Default: us-east1)"
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
    echo -e "${BOLD}Available Regions:${NC}"
    echo "  1) US East        - $us_region (N. Virginia)"
    echo "  2) India (Mumbai) - $india_region"
    echo "  3) Custom region"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-3) [1]: " choice
        choice=${choice:-1}
        case "$choice" in
            1) 
                REGION="$us_region"
                PREFERRED_REGION="us"
                break 
                ;;
            2) 
                REGION="$india_region"
                PREFERRED_REGION="india"
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
# GPU Instance Display
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
    echo -e "  └─ Languages:        1,600+ supported"
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
            
            echo -e "  ${GREEN}1)${NC}   Standard_NV36ads_A10_v5   NVIDIA A10     24 GB     36        440 GB"
            echo -e "  ${GREEN}2)${NC}   Standard_NC24ads_A100_v4  NVIDIA A100    80 GB     24        220 GB"
            echo -e "  ${GREEN}3)${NC}   Standard_NC48ads_A100_v4  NVIDIA A100 x2 160 GB    48        440 GB"
            ;;
        gcp)
            echo -e "  ${BOLD}Region: ${CYAN}$region${NC}"
            echo ""
            printf "  ${BOLD}%-5s %-25s %-15s %-10s %-10s %-10s${NC}\n" "#" "Configuration" "GPU" "VRAM" "vCPUs" "RAM"
            echo -e "  ────────────────────────────────────────────────────────────────────────────"
            
            echo -e "  ${GREEN}1)${NC}   n1-standard-16 + L4      NVIDIA L4      24 GB     16        60 GB"
            echo -e "  ${GREEN}2)${NC}   a2-highgpu-1g            NVIDIA A100    40 GB     12        85 GB"
            echo -e "  ${GREEN}3)${NC}   a2-ultragpu-1g           NVIDIA A100    80 GB     12        170 GB"
            ;;
    esac
    echo ""
}

# ==============================================================================
# Template Selection
# ==============================================================================

select_template() {
    echo ""
    log "STEP" "Select deployment template"
    
    show_model_requirements
    show_compatible_gpus
    show_gpu_instance_options "$PLATFORM" "$REGION"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📦 Deployment Templates${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    case "$PLATFORM" in
        aws)
            echo -e "  ${GREEN}1)${NC} ${CYAN}Standard${NC} - g5.4xlarge (A10G 24GB) ~\$1.00/hr"
            echo -e "  ${GREEN}2)${NC} ${CYAN}High Memory${NC} - g5.8xlarge (A10G 24GB) ~\$1.60/hr"
            echo -e "  ${GREEN}3)${NC} ${CYAN}Multi-GPU${NC} - g5.12xlarge (A10G x4) ~\$4.00/hr"
            echo -e "  ${YELLOW}4)${NC} ${CYAN}Custom${NC} - Configure manually"
            local max_options=4
            ;;
        azure)
            echo -e "  ${GREEN}1)${NC} ${CYAN}Standard${NC} - NV36ads_A10_v5 (A10 24GB) ~\$1.80/hr"
            echo -e "  ${GREEN}2)${NC} ${CYAN}Premium${NC} - NC24ads_A100_v4 (A100 80GB) ~\$3.70/hr"
            echo -e "  ${GREEN}3)${NC} ${CYAN}Multi-GPU${NC} - NC48ads_A100_v4 (A100 x2) ~\$7.40/hr"
            echo -e "  ${YELLOW}4)${NC} ${CYAN}Custom${NC} - Configure manually"
            local max_options=4
            ;;
        gcp)
            echo -e "  ${GREEN}1)${NC} ${CYAN}Standard${NC} - n1-standard-16 + L4 (24GB) ~\$0.80/hr"
            echo -e "  ${GREEN}2)${NC} ${CYAN}Premium${NC} - a2-highgpu-1g (A100 40GB) ~\$3.50/hr"
            echo -e "  ${GREEN}3)${NC} ${CYAN}Ultra${NC} - a2-ultragpu-1g (A100 80GB) ~\$5.00/hr"
            echo -e "  ${YELLOW}4)${NC} ${CYAN}Custom${NC} - Configure manually"
            local max_options=4
            ;;
        onprem)
            echo -e "  ${GREEN}1)${NC} ${CYAN}Standard${NC} - Single GPU deployment"
            echo -e "  ${GREEN}2)${NC} ${CYAN}High Availability${NC} - Multi-node with load balancing"
            echo -e "  ${YELLOW}3)${NC} ${CYAN}Custom${NC} - Configure manually"
            local max_options=3
            ;;
    esac
    echo ""
    
    while true; do
        read -p "Enter your choice (1-$max_options) [1]: " choice
        choice=${choice:-1}
        
        if [[ "$choice" -ge 1 && "$choice" -le "$max_options" ]]; then
            set_template_config "$PLATFORM" "$choice"
            break
        else
            echo -e "${RED}Invalid choice. Please enter 1-$max_options.${NC}"
        fi
    done
    
    log "SUCCESS" "Selected template: $TEMPLATE"
}

set_template_config() {
    local platform="$1"
    local choice="$2"
    
    case "$platform" in
        aws)
            case "$choice" in
                1) TEMPLATE="standard"; INSTANCE_TYPE="g5.4xlarge"; VOLUME_SIZE=100 ;;
                2) TEMPLATE="highmem"; INSTANCE_TYPE="g5.8xlarge"; VOLUME_SIZE=200 ;;
                3) TEMPLATE="multigpu"; INSTANCE_TYPE="g5.12xlarge"; VOLUME_SIZE=500 ;;
                4) TEMPLATE="custom"; configure_custom_instance ;;
            esac
            ;;
        azure)
            case "$choice" in
                1) TEMPLATE="standard"; INSTANCE_TYPE="Standard_NV36ads_A10_v5"; VOLUME_SIZE=100 ;;
                2) TEMPLATE="premium"; INSTANCE_TYPE="Standard_NC24ads_A100_v4"; VOLUME_SIZE=200 ;;
                3) TEMPLATE="multigpu"; INSTANCE_TYPE="Standard_NC48ads_A100_v4"; VOLUME_SIZE=500 ;;
                4) TEMPLATE="custom"; configure_custom_instance ;;
            esac
            ;;
        gcp)
            case "$choice" in
                1) TEMPLATE="standard"; MACHINE_TYPE="n1-standard-16"; GPU_TYPE="nvidia-l4"; GPU_COUNT=1; VOLUME_SIZE=100 ;;
                2) TEMPLATE="premium"; MACHINE_TYPE="a2-highgpu-1g"; GPU_TYPE="nvidia-tesla-a100"; GPU_COUNT=1; VOLUME_SIZE=200 ;;
                3) TEMPLATE="ultra"; MACHINE_TYPE="a2-ultragpu-1g"; GPU_TYPE="nvidia-tesla-a100"; GPU_COUNT=1; VOLUME_SIZE=500 ;;
                4) TEMPLATE="custom"; configure_custom_instance ;;
            esac
            ;;
        onprem)
            case "$choice" in
                1) TEMPLATE="onprem-standard" ;;
                2) TEMPLATE="onprem-ha" ;;
                3) TEMPLATE="custom" ;;
            esac
            ;;
    esac
}

configure_custom_instance() {
    echo ""
    echo -e "${BOLD}Custom Instance Configuration${NC}"
    echo ""
    
    case "$PLATFORM" in
        aws)
            read -p "Enter instance type [g5.4xlarge]: " INSTANCE_TYPE
            INSTANCE_TYPE=${INSTANCE_TYPE:-g5.4xlarge}
            ;;
        azure)
            read -p "Enter VM size [Standard_NV36ads_A10_v5]: " INSTANCE_TYPE
            INSTANCE_TYPE=${INSTANCE_TYPE:-Standard_NV36ads_A10_v5}
            ;;
        gcp)
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
