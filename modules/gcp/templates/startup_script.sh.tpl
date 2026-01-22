#!/bin/bash
# ==============================================================================
# GCP GPU Instance Startup Script
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

log "Starting GCP GPU instance initialization..."
log "Environment: $ENVIRONMENT"

# ==============================================================================
# 1. GPU Detection
# ==============================================================================
detect_gpu() {
    log "Detecting NVIDIA GPU hardware..."
    
    if lspci | grep -i nvidia > /dev/null 2>&1; then
        log "NVIDIA GPU hardware detected"
        lspci | grep -i nvidia | tee -a "$LOG_FILE"
        return 0
    else
        log "No NVIDIA GPU hardware detected"
        return 1
    fi
}

# ==============================================================================
# 2. Install NVIDIA Drivers
# ==============================================================================
install_nvidia_driver() {
    log "Installing NVIDIA drivers..."
    
    # Update system
    apt-get update -y
    
    # Install prerequisites
    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-$(uname -r)
    
    # Use NVIDIA's CUDA repository for drivers
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID | sed -e 's/\.//g')
    
    wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/3bf863cc.pub | apt-key add -
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64 /" > /etc/apt/sources.list.d/cuda.list
    
    apt-get update -y
    
    # Install NVIDIA driver
    apt-get install -y nvidia-driver-$NVIDIA_DRIVER_VERSION
    
    log "NVIDIA driver installed"
}

# ==============================================================================
# 3. Install CUDA Toolkit
# ==============================================================================
install_cuda() {
    log "Installing CUDA toolkit $CUDA_VERSION..."
    
    CUDA_VERSION_DASHED=$(echo $CUDA_VERSION | tr '.' '-')
    apt-get install -y cuda-toolkit-$CUDA_VERSION_DASHED
    
    # Set up environment
    cat >> /etc/profile.d/cuda.sh << 'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF
    
    log "CUDA toolkit installed"
}

# ==============================================================================
# 4. Verify Installation
# ==============================================================================
verify_gpu() {
    log "Verifying GPU setup..."
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        nvidia-smi | tee -a "$LOG_FILE"
        log "GPU verification successful"
        return 0
    else
        log "GPU verification failed"
        return 1
    fi
}

# ==============================================================================
# 5. Setup Health Check Server
# ==============================================================================
setup_health_check() {
    log "Setting up health check server..."
    
    apt-get install -y python3 python3-pip
    
    cat > /opt/health_check.py << 'HEALTHEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import subprocess
import json
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ['/', '/health']:
            self.send_health()
        elif self.path == '/gpu':
            self.send_gpu_info()
        else:
            self.send_error(404)
    
    def send_health(self):
        health = {"status": "healthy", "gpu": self.check_gpu(), "platform": "gcp"}
        self.respond_json(200, health)
    
    def send_gpu_info(self):
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=name,memory.used,memory.total,utilization.gpu',
                 '--format=csv,noheader,nounits'],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                parts = result.stdout.strip().split(', ')
                info = {
                    "name": parts[0],
                    "memory_used_mb": int(parts[1]),
                    "memory_total_mb": int(parts[2]),
                    "utilization_percent": int(parts[3])
                }
                self.respond_json(200, info)
            else:
                self.respond_json(500, {"error": "nvidia-smi failed"})
        except Exception as e:
            self.respond_json(500, {"error": str(e)})
    
    def check_gpu(self):
        try:
            result = subprocess.run(['nvidia-smi'], capture_output=True, timeout=10)
            return result.returncode == 0
        except:
            return False
    
    def respond_json(self, code, data):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
    print(f"Health check on port {PORT}")
    httpd.serve_forever()
HEALTHEOF

    chmod +x /opt/health_check.py
    
    cat > /etc/systemd/system/health-check.service << EOF
[Unit]
Description=GPU Health Check Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/health_check.py $HEALTH_CHECK_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable health-check
    systemctl start health-check
    
    log "Health check server started on port $HEALTH_CHECK_PORT"
}

# ==============================================================================
# 6. Install Google Cloud Ops Agent
# ==============================================================================
setup_monitoring() {
    log "Setting up Google Cloud Ops Agent..."
    
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    rm -f add-google-cloud-ops-agent-repo.sh
    
    # Configure for GPU metrics
    cat > /etc/google-cloud-ops-agent/config.yaml << 'OPSEOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    gpu_setup:
      type: files
      include_paths:
        - /var/log/gpu-setup.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog, gpu_setup]
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
OPSEOF

    systemctl restart google-cloud-ops-agent
    
    log "Ops Agent configured"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    log "=========================================="
    log "GCP GPU Instance Setup"
    log "=========================================="
    
    # Check for GPU hardware
    if detect_gpu; then
        # Check if driver already installed
        if ! command -v nvidia-smi > /dev/null 2>&1; then
            install_nvidia_driver
            install_cuda
        fi
        
        verify_gpu
    fi
    
    # Setup health check
    setup_health_check
    
    # Setup monitoring
    setup_monitoring
    
    log "=========================================="
    log "GCP GPU Instance Setup Complete"
    log "=========================================="
    
    touch /var/log/gpu-setup-complete
}

main 2>&1 | tee -a "$LOG_FILE"
