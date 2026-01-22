# ==============================================================================
# Shared Variables for DPG GPU Infrastructure
# ==============================================================================
# These variables are common across all cloud providers and environments.
# Import this module in each cloud-specific environment configuration.
# ==============================================================================

# ------------------------------------------------------------------------------
# Project Configuration
# ------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "dpg-infra"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "OpenAgriNet"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Network Configuration
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC/VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed for HTTP/HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ------------------------------------------------------------------------------
# Compute Configuration
# ------------------------------------------------------------------------------
variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 100
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "gpu-infra-key"
}

# ------------------------------------------------------------------------------
# Auto-Scaling Configuration
# ------------------------------------------------------------------------------
variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 1
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold to trigger scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold to trigger scale down"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------------------
# Load Balancer Configuration
# ------------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Whether to create a load balancer"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path for health checks"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 8080
}

variable "health_check_interval" {
  description = "Interval between health checks (seconds)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout (seconds)"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Number of consecutive successes for healthy status"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failures for unhealthy status"
  type        = number
  default     = 3
}

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 8080
}

# ------------------------------------------------------------------------------
# NVIDIA Configuration
# ------------------------------------------------------------------------------
variable "nvidia_driver_version" {
  description = "NVIDIA driver version to install"
  type        = string
  default     = "550"
}

variable "cuda_version" {
  description = "CUDA toolkit version to install"
  type        = string
  default     = "12.4"
}

# ------------------------------------------------------------------------------
# Scheduling Configuration
# ------------------------------------------------------------------------------
variable "enable_scheduling" {
  description = "Enable start/stop scheduling for cost savings"
  type        = bool
  default     = true
}

variable "schedule_start_cron" {
  description = "Cron expression for starting instances (UTC)"
  type        = string
  default     = "cron(0 4 ? * MON-FRI *)"  # 4:00 AM UTC = 9:30 AM IST
}

variable "schedule_stop_cron" {
  description = "Cron expression for stopping instances (UTC)"
  type        = string
  default     = "cron(0 15 ? * MON-FRI *)"  # 3:00 PM UTC = 6:00 PM Ethiopia
}
