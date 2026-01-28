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

# ==============================================================================
# Instance Pricing Type Selection (Spot vs On-Demand)
# ==============================================================================

select_instance_pricing() {
    # Only applicable for AWS currently
    if [[ "$PLATFORM" != "aws" ]]; then
        USE_SPOT_INSTANCES="false"
        return
    fi
    
    echo ""
    log "STEP" "Select instance pricing type"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  💰 Instance Pricing Options${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${CYAN}On-Demand${NC} - Pay full price, guaranteed availability"
    echo -e "     └─ Best for: Production workloads, predictable availability"
    echo ""
    echo -e "  ${GREEN}2)${NC} ${CYAN}Spot Instances${NC} - Up to 90% savings, may be interrupted"
    echo -e "     └─ Best for: Development, testing, fault-tolerant workloads"
    echo -e "     └─ ${YELLOW}Note: Instances may be terminated with 2-min warning${NC}"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-2) [1]: " choice
        choice=${choice:-1}
        case "$choice" in
            1) 
                USE_SPOT_INSTANCES="false"
                log "SUCCESS" "Selected: On-Demand instances"
                break 
                ;;
            2) 
                USE_SPOT_INSTANCES="true"
                log "SUCCESS" "Selected: Spot instances (cost savings enabled)"
                # Run spot capacity check
                if ! check_spot_capacity; then
                    log "WARN" "Spot capacity check indicated potential issues"
                fi
                break 
                ;;
            *) echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}" ;;
        esac
    done
}

# ==============================================================================
# Spot Instance Capacity Check
# ==============================================================================
# Checks AWS Spot capacity for the selected instance type and availability
# zones, and warns the user if capacity may not be available.
# ==============================================================================

check_spot_capacity() {
    local instance_type="${INSTANCE_TYPE:-g5.4xlarge}"
    local region="${REGION:-us-east-1}"
    
    # Get the configured availability zones (default to a/b suffixes)
    local az1="${region}a"
    local az2="${region}b"
    local selected_azs="${az1},${az2}"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  Spot Instance Capacity Check${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    log "INFO" "Instance Type: ${BOLD}$instance_type${NC}"
    log "INFO" "Region: ${BOLD}$region${NC}"
    log "INFO" "Selected AZs: ${BOLD}$az1, $az2${NC}"
    echo ""
    log "INFO" "Checking Spot capacity availability..."
    echo ""
    
    # Arrays to track results
    local available_azs=()
    local unavailable_azs=()
    local az_with_prices=()
    
    # Get all AZs in the region
    local all_azs
    all_azs=$(aws ec2 describe-availability-zones \
        --region "$region" \
        --filters "Name=state,Values=available" \
        --query 'AvailabilityZones[*].ZoneName' \
        --output text 2>/dev/null | tr '\t' '\n' | sort)
    
    if [[ -z "$all_azs" ]]; then
        log "WARN" "Could not retrieve availability zones"
        return 0
    fi
    
    # Check each AZ for spot pricing (indicates availability)
    for az in $all_azs; do
        printf "  Checking %-15s ... " "$az"
        
        local price
        price=$(aws ec2 describe-spot-price-history \
            --region "$region" \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --start-time "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')" \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text 2>/dev/null)
        
        if [[ -n "$price" && "$price" != "None" && "$price" != "null" ]]; then
            echo -e "${GREEN}Available${NC} (Spot price: \$${price}/hr)"
            available_azs+=("$az")
            az_with_prices+=("$az:\$${price}/hr")
        else
            echo -e "${YELLOW}Limited/Unavailable${NC}"
            unavailable_azs+=("$az")
        fi
    done
    
    echo ""
    
    # Check if selected AZs have capacity issues
    local selected_with_issues=()
    local selected_ok=()
    
    for selected_az in "$az1" "$az2"; do
        local found_unavailable=false
        for unavail_az in "${unavailable_azs[@]}"; do
            if [[ "$selected_az" == "$unavail_az" ]]; then
                selected_with_issues+=("$selected_az")
                found_unavailable=true
                break
            fi
        done
        if [[ "$found_unavailable" == "false" ]]; then
            selected_ok+=("$selected_az")
        fi
    done
    
    # Report results
    if [[ ${#selected_with_issues[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}${BOLD}  ⚠ SPOT CAPACITY WARNING${NC}"
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  The ${BOLD}$instance_type${NC} Spot capacity is ${RED}not available${NC} in:"
        for issue_az in "${selected_with_issues[@]}"; do
            echo -e "    ${RED}•${NC} $issue_az"
        done
        echo ""
        echo -e "  The ASG is configured to use: ${BOLD}$az1${NC} and ${BOLD}$az2${NC}"
        echo ""
        
        # Find alternative AZs
        local alternative_azs=()
        for avail_az in "${available_azs[@]}"; do
            if [[ "$avail_az" != "$az1" && "$avail_az" != "$az2" ]]; then
                alternative_azs+=("$avail_az")
            fi
        done
        
        if [[ ${#alternative_azs[@]} -gt 0 ]]; then
            echo -e "  ${GREEN}${BOLD}Recommended Alternatives:${NC}"
            echo -e "  According to current Spot pricing, capacity is available in:"
            for alt_az in "${alternative_azs[@]}"; do
                # Find price for this AZ
                local az_price=""
                for price_entry in "${az_with_prices[@]}"; do
                    if [[ "$price_entry" == "$alt_az:"* ]]; then
                        az_price="${price_entry#*:}"
                        break
                    fi
                done
                if [[ -n "$az_price" ]]; then
                    echo -e "    ${GREEN}•${NC} $alt_az (Spot: ${az_price})"
                else
                    echo -e "    ${GREEN}•${NC} $alt_az"
                fi
            done
            echo ""
            
            # Suggest first two available alternatives
            local suggested_az1="${alternative_azs[0]:-}"
            local suggested_az2="${alternative_azs[1]:-$suggested_az1}"
            
            echo -e "  ${BOLD}To use recommended AZs, update your terraform.tfvars:${NC}"
            echo -e "    ${CYAN}availability_zones = [\"$suggested_az1\", \"$suggested_az2\"]${NC}"
            echo ""
        fi
        
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Prompt user for action
        echo -e "${BOLD}Options:${NC}"
        echo -e "  ${GREEN}1)${NC} Continue anyway (instances may fail to launch)"
        echo -e "  ${GREEN}2)${NC} Cancel and update availability zones manually"
        
        if [[ ${#alternative_azs[@]} -ge 2 ]]; then
            echo -e "  ${GREEN}3)${NC} Auto-update to use ${alternative_azs[0]} and ${alternative_azs[1]}"
        fi
        echo ""
        
        local max_choice=2
        [[ ${#alternative_azs[@]} -ge 2 ]] && max_choice=3
        
        while true; do
            read -p "Enter your choice (1-$max_choice): " capacity_choice
            case "$capacity_choice" in
                1)
                    log "WARN" "Continuing with current AZs - Spot instances may fail to launch"
                    return 0
                    ;;
                2)
                    log "INFO" "Deployment cancelled. Please update availability_zones in terraform.tfvars"
                    exit 1
                    ;;
                3)
                    if [[ $max_choice -ge 3 ]]; then
                        log "INFO" "Auto-updating availability zones to ${alternative_azs[0]} and ${alternative_azs[1]}"
                        # Store for later use in config generation
                        AVAILABILITY_ZONES="${alternative_azs[0]},${alternative_azs[1]}"
                        AZ1="${alternative_azs[0]}"
                        AZ2="${alternative_azs[1]}"
                        log "SUCCESS" "Availability zones updated"
                        return 0
                    else
                        echo -e "${RED}Invalid choice.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1-$max_choice.${NC}"
                    ;;
            esac
        done
    else
        log "SUCCESS" "Spot capacity is available in selected AZs!"
        return 0
    fi
}
