# ==============================================================================
# AWS Module Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# General
# ------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

# ------------------------------------------------------------------------------
# Network
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed for HTTP/HTTPS access"
  type        = list(string)
}

# ------------------------------------------------------------------------------
# Compute
# ------------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
}

variable "root_volume_type" {
  description = "Root volume type"
  type        = string
}

variable "key_name" {
  description = "SSH key name"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

# ------------------------------------------------------------------------------
# Auto-Scaling
# ------------------------------------------------------------------------------
variable "asg_min_size" {
  description = "Minimum ASG size"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum ASG size"
  type        = number
}

variable "asg_desired_capacity" {
  description = "Desired ASG capacity"
  type        = number
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
}

# ------------------------------------------------------------------------------
# Load Balancer
# ------------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Enable ALB"
  type        = bool
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
}

variable "health_check_port" {
  description = "Health check port"
  type        = number
}

variable "health_check_interval" {
  description = "Health check interval"
  type        = number
}

variable "health_check_timeout" {
  description = "Health check timeout"
  type        = number
}

variable "healthy_threshold" {
  description = "Healthy threshold count"
  type        = number
}

variable "unhealthy_threshold" {
  description = "Unhealthy threshold count"
  type        = number
}

variable "app_port" {
  description = "Application port"
  type        = number
}

# ------------------------------------------------------------------------------
# NVIDIA
# ------------------------------------------------------------------------------
variable "nvidia_driver_version" {
  description = "NVIDIA driver version"
  type        = string
}

variable "cuda_version" {
  description = "CUDA toolkit version"
  type        = string
}

# ------------------------------------------------------------------------------
# Scheduling
# ------------------------------------------------------------------------------
variable "enable_scheduling" {
  description = "Enable scheduled start/stop"
  type        = bool
}

variable "schedule_start_cron" {
  description = "Cron expression for start time"
  type        = string
}

variable "schedule_stop_cron" {
  description = "Cron expression for stop time"
  type        = string
}
