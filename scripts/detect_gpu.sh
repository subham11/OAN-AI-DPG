#!/bin/bash
# ==============================================================================
# Local GPU Detection Script
# ==============================================================================
# This script detects whether NVIDIA GPU hardware and drivers are present
# on the local machine. It's used during Terraform initialization to determine
# if cloud resources need to be provisioned.
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output file for Terraform
OUTPUT_FILE="${1:-/tmp/gpu_detection.json}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}NVIDIA GPU Detection Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Initialize results
GPU_HARDWARE_PRESENT="false"
GPU_DRIVER_INSTALLED="false"
GPU_NAME=""
GPU_DRIVER_VERSION=""
GPU_MEMORY_TOTAL=""
CUDA_VERSION=""
NEEDS_CLOUD_DEPLOYMENT="false"

# ==============================================================================
# Step 1: Check for NVIDIA hardware using lspci
# ==============================================================================
echo -e "\n${YELLOW}Step 1: Checking for NVIDIA GPU hardware...${NC}"

if command -v lspci &> /dev/null; then
    NVIDIA_HARDWARE=$(lspci | grep -i nvidia || true)
    
    if [ -n "$NVIDIA_HARDWARE" ]; then
        echo -e "${GREEN}✓ NVIDIA GPU hardware detected${NC}"
        echo "$NVIDIA_HARDWARE"
        GPU_HARDWARE_PRESENT="true"
    else
        echo -e "${RED}✗ No NVIDIA GPU hardware found${NC}"
        GPU_HARDWARE_PRESENT="false"
    fi
else
    echo -e "${YELLOW}⚠ lspci command not available${NC}"
    # Try alternative method on Mac
    if [ "$(uname)" = "Darwin" ]; then
        if system_profiler SPDisplaysDataType 2>/dev/null | grep -i nvidia &> /dev/null; then
            echo -e "${GREEN}✓ NVIDIA GPU hardware detected (macOS)${NC}"
            GPU_HARDWARE_PRESENT="true"
        fi
    fi
fi

# ==============================================================================
# Step 2: Check for NVIDIA driver using nvidia-smi
# ==============================================================================
echo -e "\n${YELLOW}Step 2: Checking for NVIDIA driver...${NC}"

if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ NVIDIA driver is installed and working${NC}"
        GPU_DRIVER_INSTALLED="true"
        
        # Get GPU information
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        GPU_DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        GPU_MEMORY_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        
        echo "  GPU Name: $GPU_NAME"
        echo "  Driver Version: $GPU_DRIVER_VERSION"
        echo "  Memory: $GPU_MEMORY_TOTAL"
    else
        echo -e "${RED}✗ nvidia-smi found but failed to execute${NC}"
        GPU_DRIVER_INSTALLED="false"
    fi
else
    echo -e "${RED}✗ nvidia-smi not found - NVIDIA driver not installed${NC}"
    GPU_DRIVER_INSTALLED="false"
fi

# ==============================================================================
# Step 3: Check for CUDA toolkit
# ==============================================================================
echo -e "\n${YELLOW}Step 3: Checking for CUDA toolkit...${NC}"

if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p' || echo "Unknown")
    echo -e "${GREEN}✓ CUDA toolkit installed: $CUDA_VERSION${NC}"
else
    echo -e "${RED}✗ CUDA toolkit not found${NC}"
    CUDA_VERSION=""
fi

# ==============================================================================
# Step 4: Determine if cloud deployment is needed
# ==============================================================================
echo -e "\n${YELLOW}Step 4: Determining deployment requirement...${NC}"

if [ "$GPU_HARDWARE_PRESENT" = "false" ]; then
    echo -e "${BLUE}→ No local GPU hardware - cloud deployment recommended${NC}"
    NEEDS_CLOUD_DEPLOYMENT="true"
elif [ "$GPU_DRIVER_INSTALLED" = "false" ]; then
    echo -e "${YELLOW}→ GPU hardware present but driver not installed${NC}"
    echo -e "${BLUE}→ Driver can be installed locally, or use cloud deployment${NC}"
    NEEDS_CLOUD_DEPLOYMENT="optional"
else
    echo -e "${GREEN}→ Local GPU is ready - cloud deployment optional${NC}"
    NEEDS_CLOUD_DEPLOYMENT="false"
fi

# ==============================================================================
# Generate JSON output
# ==============================================================================
cat > "$OUTPUT_FILE" << EOF
{
    "gpu_hardware_present": $GPU_HARDWARE_PRESENT,
    "gpu_driver_installed": $GPU_DRIVER_INSTALLED,
    "gpu_name": "$GPU_NAME",
    "gpu_driver_version": "$GPU_DRIVER_VERSION",
    "gpu_memory_total": "$GPU_MEMORY_TOTAL",
    "cuda_version": "$CUDA_VERSION",
    "needs_cloud_deployment": "$NEEDS_CLOUD_DEPLOYMENT",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Detection Results Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "GPU Hardware Present: $([ "$GPU_HARDWARE_PRESENT" = "true" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
echo -e "GPU Driver Installed: $([ "$GPU_DRIVER_INSTALLED" = "true" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
echo -e "Cloud Deployment Needed: $NEEDS_CLOUD_DEPLOYMENT"
echo -e "\nResults saved to: $OUTPUT_FILE"
echo -e "${BLUE}========================================${NC}"

# Exit with appropriate code
if [ "$NEEDS_CLOUD_DEPLOYMENT" = "true" ]; then
    exit 1  # Indicates cloud deployment is required
else
    exit 0  # Local GPU is available
fi
