# ==============================================================================
# Azure Staging Environment - Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# Azure Authentication
# ------------------------------------------------------------------------------
variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  default     = ""
}

variable "azure_client_id" {
  description = "Azure Service Principal Client ID"
  type        = string
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_use_msi" {
  description = "Use Managed Service Identity"
  type        = bool
  default     = false
}

variable "azure_use_cli" {
  description = "Use Azure CLI authentication"
  type        = bool
  default     = true
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"
}

# ------------------------------------------------------------------------------
# Project Configuration
# ------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "dpg-infra"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "staging"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "OAN"
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Network Configuration
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VNet"
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
  description = "CIDR blocks allowed for SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed for HTTP"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ------------------------------------------------------------------------------
# Compute Configuration
# ------------------------------------------------------------------------------
variable "instance_type" {
  description = "Azure VM size for GPU instances"
  type        = string
  default     = "Standard_NC6s_v3"
}

variable "root_volume_size" {
  description = "Size of OS disk in GB"
  type        = number
  default     = 128
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Auto-Scaling Configuration
# ------------------------------------------------------------------------------
variable "asg_min_size" {
  description = "Minimum instances"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum instances"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired instances"
  type        = number
  default     = 1
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold for scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold for scale down"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------------------
# Load Balancer Configuration
# ------------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Create load balancer"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Health check port"
  type        = number
  default     = 8080
}

variable "health_check_interval" {
  description = "Health check interval"
  type        = number
  default     = 30
}

variable "healthy_threshold" {
  description = "Healthy threshold"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Unhealthy threshold"
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
  description = "NVIDIA driver version"
  type        = string
  default     = "550"
}

variable "cuda_version" {
  description = "CUDA version"
  type        = string
  default     = "12.4"
}

# ------------------------------------------------------------------------------
# Scheduling Configuration
# ------------------------------------------------------------------------------
variable "enable_scheduling" {
  description = "Enable scheduling"
  type        = bool
  default     = true
}

variable "schedule_start_cron" {
  description = "Start cron (UTC)"
  type        = string
  default     = "0 4 * * 1-5"
}

variable "schedule_stop_cron" {
  description = "Stop cron (UTC)"
  type        = string
  default     = "0 15 * * 1-5"
}
