# ==============================================================================
# GCP Staging Environment - Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# GCP Authentication
# ------------------------------------------------------------------------------
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "asia-south1"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-south1-a"
}

variable "gcp_credentials_file" {
  description = "Path to GCP credentials JSON file"
  type        = string
  default     = ""
}

variable "gcp_credentials_json" {
  description = "GCP credentials JSON content"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gcp_access_token" {
  description = "GCP access token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gcp_impersonate_service_account" {
  description = "Service account to impersonate"
  type        = string
  default     = ""
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
  description = "Additional labels"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Network Configuration
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
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
variable "machine_type" {
  description = "GCP machine type"
  type        = string
  default     = "n1-standard-4"
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "Number of GPUs per instance"
  type        = number
  default     = 1
}

variable "root_volume_size" {
  description = "Size of boot disk in GB"
  type        = number
  default     = 100
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
