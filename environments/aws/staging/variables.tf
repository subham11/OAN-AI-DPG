# ==============================================================================
# AWS Staging Environment - Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# AWS Authentication
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = ""
}

variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token (for temporary credentials)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS Account ID for validation"
  type        = string
  default     = ""
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
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
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Network Configuration
# ------------------------------------------------------------------------------

# Existing VPC/Subnet Reuse Options
variable "use_existing_vpc" {
  description = "Use an existing VPC instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (only if use_existing_vpc = true)"
  type        = string
  default     = ""
}

variable "existing_public_subnet_ids" {
  description = "IDs of existing public subnets to use (only if use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

variable "existing_private_subnet_ids" {
  description = "IDs of existing private subnets to use (only if use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

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
variable "instance_type" {
  description = "EC2 instance type for GPU instances"
  type        = string
  default     = "g4dn.xlarge"
}

variable "use_spot_instances" {
  description = "Use Spot instances instead of On-Demand (cost savings but may be interrupted)"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (empty string means on-demand price cap)"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 100
}

variable "root_volume_type" {
  description = "Type of root volume (gp3, gp2, io1)"
  type        = string
  default     = "gp3"
}

variable "key_name" {
  description = "Name of SSH key pair"
  type        = string
  default     = "gpu-infra-key"
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
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 1
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 30
}

variable "health_check_grace_period" {
  description = "Grace period for health checks (seconds)"
  type        = number
  default     = 300
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
  description = "Interval between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Healthy threshold count"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Unhealthy threshold count"
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
  description = "CUDA toolkit version"
  type        = string
  default     = "12.4"
}

# ------------------------------------------------------------------------------
# Scheduling Configuration
# ------------------------------------------------------------------------------
variable "enable_scheduling" {
  description = "Enable start/stop scheduling"
  type        = bool
  default     = true
}

variable "schedule_start_cron" {
  description = "Cron expression for start (UTC)"
  type        = string
  default     = "cron(0 4 ? * MON-FRI *)"
}

variable "schedule_stop_cron" {
  description = "Cron expression for stop (UTC)"
  type        = string
  default     = "cron(0 15 ? * MON-FRI *)"
}
