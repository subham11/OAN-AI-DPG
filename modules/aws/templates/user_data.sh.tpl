#!/bin/bash
# ==============================================================================
# GPU Instance Initialization Script
# ==============================================================================
# This script handles:
# 1. GPU detection
# 2. NVIDIA driver installation (if needed)
# 3. CUDA toolkit setup
# 4. Health check endpoint
# 5. CloudWatch agent for GPU metrics
# ==============================================================================

set -euo pipefail

# Variables
NVIDIA_DRIVER_VERSION="${nvidia_driver_version}"
CUDA_VERSION="${cuda_version}"
HEALTH_CHECK_PORT="${health_check_port}"
ENVIRONMENT="${environment}"
LOG_FILE="/var/log/gpu-setup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting GPU instance initialization..."

# ==============================================================================
# 1. GPU Detection
# ==============================================================================
detect_gpu() {
    log "Detecting NVIDIA GPU hardware..."
    
    # Check for NVIDIA hardware using lspci
    if lspci | grep -i nvidia > /dev/null 2>&1; then
        log "NVIDIA GPU hardware detected via lspci"
        GPU_HARDWARE_PRESENT=true
    else
        log "No NVIDIA GPU hardware detected"
        GPU_HARDWARE_PRESENT=false
        return 1
    fi
    
    # Check if NVIDIA driver is installed
    if command -v nvidia-smi > /dev/null 2>&1; then
        log "NVIDIA driver is installed"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv | tee -a "$LOG_FILE"
        NVIDIA_DRIVER_INSTALLED=true
    else
        log "NVIDIA driver NOT installed"
        NVIDIA_DRIVER_INSTALLED=false
    fi
    
    return 0
}

# ==============================================================================
# 2. NVIDIA Driver Installation
# ==============================================================================
install_nvidia_driver() {
    log "Installing NVIDIA driver version $NVIDIA_DRIVER_VERSION..."
    
    # Update system
    apt-get update -y || error_exit "Failed to update apt"
    
    # Install prerequisites
    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-$(uname -r) \
        || error_exit "Failed to install prerequisites"
    
    # Add NVIDIA repository
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID | sed -e 's/\.//g')
    
    wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/3bf863cc.pub | apt-key add -
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64 /" > /etc/apt/sources.list.d/cuda.list
    
    apt-get update -y || error_exit "Failed to update apt after adding NVIDIA repo"
    
    # Install NVIDIA driver
    apt-get install -y nvidia-driver-$NVIDIA_DRIVER_VERSION || error_exit "Failed to install NVIDIA driver"
    
    log "NVIDIA driver installed successfully"
}

# ==============================================================================
# 3. CUDA Toolkit Installation
# ==============================================================================
install_cuda() {
    log "Installing CUDA toolkit version $CUDA_VERSION..."
    
    # Install CUDA toolkit
    CUDA_VERSION_DASHED=$(echo $CUDA_VERSION | tr '.' '-')
    apt-get install -y cuda-toolkit-$CUDA_VERSION_DASHED || error_exit "Failed to install CUDA toolkit"
    
    # Set up environment variables
    cat >> /etc/profile.d/cuda.sh << 'CUDAEOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
CUDAEOF
    
    source /etc/profile.d/cuda.sh
    
    log "CUDA toolkit installed successfully"
}

# ==============================================================================
# 4. Verify Installation
# ==============================================================================
verify_installation() {
    log "Verifying GPU setup..."
    
    # Test nvidia-smi
    if nvidia-smi > /dev/null 2>&1; then
        log "nvidia-smi working correctly"
        nvidia-smi | tee -a "$LOG_FILE"
    else
        error_exit "nvidia-smi failed"
    fi
    
    # Test CUDA
    if command -v nvcc > /dev/null 2>&1; then
        log "CUDA compiler available"
        nvcc --version | tee -a "$LOG_FILE"
    else
        log "WARNING: nvcc not found in PATH"
    fi
    
    log "GPU verification complete"
}

# ==============================================================================
# 5. Health Check Endpoint
# ==============================================================================
setup_health_check() {
    log "Setting up health check endpoint on port $HEALTH_CHECK_PORT..."
    
    # Install Python if not present
    apt-get install -y python3 python3-pip || true
    
    # Create health check script
    cat > /opt/health_check.py << 'HEALTHEOF'
#!/usr/bin/env python3
"""
Simple HTTP health check server
Returns GPU status and system health
"""
import http.server
import socketserver
import subprocess
import json
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_health_response()
        elif self.path == '/gpu':
            self.send_gpu_response()
        else:
            self.send_error(404)
    
    def send_health_response(self):
        health = {
            "status": "healthy",
            "gpu_available": self.check_gpu(),
            "service": "gpu-instance"
        }
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(health).encode())
    
    def send_gpu_response(self):
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=name,memory.used,memory.total,utilization.gpu', '--format=csv,noheader,nounits'],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                parts = result.stdout.strip().split(', ')
                gpu_info = {
                    "name": parts[0],
                    "memory_used_mb": int(parts[1]),
                    "memory_total_mb": int(parts[2]),
                    "utilization_percent": int(parts[3])
                }
                status_code = 200
            else:
                gpu_info = {"error": "nvidia-smi failed"}
                status_code = 500
        except Exception as e:
            gpu_info = {"error": str(e)}
            status_code = 500
        
        self.send_response(status_code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(gpu_info).encode())
    
    def check_gpu(self):
        try:
            result = subprocess.run(['nvidia-smi'], capture_output=True, timeout=10)
            return result.returncode == 0
        except:
            return False
    
    def log_message(self, format, *args):
        pass  # Suppress logs

with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
    print(f"Health check server running on port {PORT}")
    httpd.serve_forever()
HEALTHEOF

    chmod +x /opt/health_check.py
    
    # Create systemd service
    cat > /etc/systemd/system/health-check.service << SERVICEEOF
[Unit]
Description=GPU Instance Health Check Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/health_check.py $HEALTH_CHECK_PORT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable health-check
    systemctl start health-check
    
    log "Health check endpoint started on port $HEALTH_CHECK_PORT"
}

# ==============================================================================
# 6. CloudWatch Agent for GPU Metrics
# ==============================================================================
setup_cloudwatch_agent() {
    log "Setting up CloudWatch agent for GPU metrics..."
    
    # Install CloudWatch agent
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i -E ./amazon-cloudwatch-agent.deb || true
    rm -f amazon-cloudwatch-agent.deb
    
    # Create CloudWatch agent config
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "metrics": {
        "namespace": "Custom/GPU",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_active"],
                "metrics_collection_interval": 60
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["disk_used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["/"]
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/gpu-setup.log",
                        "log_group_name": "/gpu-instances/setup",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/syslog",
                        "log_group_name": "/gpu-instances/syslog",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
CWEOF

    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
    
    # Create GPU metrics collection script
    cat > /opt/gpu_metrics.sh << 'GPUMETRICSEOF'
#!/bin/bash
# Collect GPU metrics and publish to CloudWatch

while true; do
    if command -v nvidia-smi > /dev/null 2>&1; then
        # Get GPU metrics
        GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        GPU_MEM=$(nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits 2>/dev/null | head -1)
        GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        
        INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        
        # Publish to CloudWatch
        if [ -n "$GPU_UTIL" ]; then
            aws cloudwatch put-metric-data \
                --namespace "Custom/GPU" \
                --metric-name "GPUUtilization" \
                --value "$GPU_UTIL" \
                --unit "Percent" \
                --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null || true
        fi
        
        if [ -n "$GPU_MEM" ]; then
            aws cloudwatch put-metric-data \
                --namespace "Custom/GPU" \
                --metric-name "GPUMemoryUtilization" \
                --value "$GPU_MEM" \
                --unit "Percent" \
                --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null || true
        fi
        
        if [ -n "$GPU_TEMP" ]; then
            aws cloudwatch put-metric-data \
                --namespace "Custom/GPU" \
                --metric-name "GPUTemperature" \
                --value "$GPU_TEMP" \
                --unit "None" \
                --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null || true
        fi
    fi
    
    sleep 60
done
GPUMETRICSEOF

    chmod +x /opt/gpu_metrics.sh
    
    # Create systemd service for GPU metrics
    cat > /etc/systemd/system/gpu-metrics.service << 'GPUSERVICEEOF'
[Unit]
Description=GPU Metrics Collection
After=network.target

[Service]
Type=simple
ExecStart=/opt/gpu_metrics.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
GPUSERVICEEOF

    systemctl daemon-reload
    systemctl enable gpu-metrics
    systemctl start gpu-metrics
    
    log "CloudWatch agent configured"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    log "=========================================="
    log "GPU Instance Setup - Environment: $ENVIRONMENT"
    log "=========================================="
    
    # Detect GPU
    detect_gpu || true
    
    # Install NVIDIA driver if hardware present but driver not installed
    if [ "$GPU_HARDWARE_PRESENT" = true ] && [ "$NVIDIA_DRIVER_INSTALLED" = false ]; then
        install_nvidia_driver
        install_cuda
    fi
    
    # Verify installation
    if [ "$GPU_HARDWARE_PRESENT" = true ]; then
        verify_installation
    fi
    
    # Setup health check
    setup_health_check
    
    # Setup CloudWatch agent
    setup_cloudwatch_agent
    
    log "=========================================="
    log "GPU Instance Setup Complete"
    log "=========================================="
    
    # Signal success
    touch /var/log/gpu-setup-complete
}

# Run main
main 2>&1 | tee -a "$LOG_FILE"
