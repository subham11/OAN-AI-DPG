#cloud-config
# ==============================================================================
# Azure GPU Instance Cloud-Init Configuration
# ==============================================================================

package_update: true
package_upgrade: true

packages:
  - python3
  - python3-pip
  - build-essential
  - dkms
  - curl
  - wget
  - jq
  - htop
  - nvtop

write_files:
  # GPU Detection Script
  - path: /opt/scripts/detect_gpu.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # GPU Detection Script
      
      LOG_FILE="/var/log/gpu-setup.log"
      
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
      }
      
      # Check for NVIDIA hardware
      if lspci | grep -i nvidia > /dev/null 2>&1; then
          log "NVIDIA GPU hardware detected"
          GPU_HARDWARE=true
      else
          log "No NVIDIA GPU hardware found"
          GPU_HARDWARE=false
      fi
      
      # Check for NVIDIA driver
      if command -v nvidia-smi > /dev/null 2>&1; then
          log "NVIDIA driver installed"
          nvidia-smi | tee -a "$LOG_FILE"
          DRIVER_INSTALLED=true
      else
          log "NVIDIA driver not installed"
          DRIVER_INSTALLED=false
      fi
      
      echo "GPU_HARDWARE=$GPU_HARDWARE"
      echo "DRIVER_INSTALLED=$DRIVER_INSTALLED"

  # Health Check Server
  - path: /opt/scripts/health_check.py
    permissions: '0755'
    content: |
      #!/usr/bin/env python3
      import http.server
      import socketserver
      import subprocess
      import json
      import sys
      
      PORT = int(sys.argv[1]) if len(sys.argv) > 1 else ${health_check_port}
      
      class HealthHandler(http.server.SimpleHTTPRequestHandler):
          def do_GET(self):
              if self.path in ['/', '/health']:
                  self.send_health()
              elif self.path == '/gpu':
                  self.send_gpu_info()
              else:
                  self.send_error(404)
          
          def send_health(self):
              health = {
                  "status": "healthy",
                  "gpu": self.check_gpu(),
                  "service": "azure-gpu-instance"
              }
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

  # Health Check Service
  - path: /etc/systemd/system/health-check.service
    content: |
      [Unit]
      Description=GPU Health Check Server
      After=network.target
      
      [Service]
      Type=simple
      ExecStart=/usr/bin/python3 /opt/scripts/health_check.py ${health_check_port}
      Restart=always
      RestartSec=5
      
      [Install]
      WantedBy=multi-user.target

  # NVIDIA Setup Script
  - path: /opt/scripts/setup_nvidia.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # NVIDIA Driver and CUDA Setup
      
      NVIDIA_VERSION="${nvidia_driver_version}"
      CUDA_VERSION="${cuda_version}"
      LOG_FILE="/var/log/gpu-setup.log"
      
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
      }
      
      log "Starting NVIDIA setup..."
      
      # The Azure NVIDIA GPU Driver extension handles most of this
      # This script is for verification and additional configuration
      
      # Wait for NVIDIA extension to complete
      MAX_WAIT=300
      WAITED=0
      while [ ! -f /var/lib/waagent/custom-script/download/0/status ]; do
          if [ $WAITED -ge $MAX_WAIT ]; then
              log "Timeout waiting for Azure extensions"
              break
          fi
          sleep 10
          WAITED=$((WAITED + 10))
      done
      
      # Verify installation
      if command -v nvidia-smi > /dev/null 2>&1; then
          log "NVIDIA driver installation verified"
          nvidia-smi | tee -a "$LOG_FILE"
      else
          log "WARNING: nvidia-smi not available"
      fi
      
      # Set up CUDA environment
      if [ -d /usr/local/cuda ]; then
          echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/profile.d/cuda.sh
          echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/profile.d/cuda.sh
          log "CUDA environment configured"
      fi
      
      log "NVIDIA setup complete"
      touch /var/log/gpu-setup-complete

runcmd:
  # Create scripts directory
  - mkdir -p /opt/scripts
  
  # Run GPU detection
  - /opt/scripts/detect_gpu.sh
  
  # Enable and start health check service
  - systemctl daemon-reload
  - systemctl enable health-check
  - systemctl start health-check
  
  # Run NVIDIA setup
  - /opt/scripts/setup_nvidia.sh
  
  # Log completion
  - echo "Cloud-init complete at $(date)" >> /var/log/gpu-setup.log

final_message: "GPU instance initialization complete after $UPTIME seconds"
