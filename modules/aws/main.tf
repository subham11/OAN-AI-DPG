# ==============================================================================
# AWS Module - Main Entry Point
# ==============================================================================

locals {
  # Deep Learning AMI (Ubuntu 22.04) - Includes NVIDIA drivers
  # This will be fetched dynamically
  ami_name_filter = "Deep Learning AMI GPU PyTorch * (Ubuntu 22.04) *"
}

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

# Get the latest Deep Learning AMI
data "aws_ami" "gpu_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [local.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Alternative: Ubuntu 22.04 base AMI (for manual NVIDIA installation)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# SSH Key Pair
# ------------------------------------------------------------------------------
resource "aws_key_pair" "main" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# User Data Script for NVIDIA Installation
# ------------------------------------------------------------------------------
locals {
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    health_check_port     = var.health_check_port
    environment           = var.environment
  })
}
