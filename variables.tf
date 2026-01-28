# ==============================================================================
# Terraform Variables - Consolidated from variables/ folder
# ==============================================================================
# This file consolidates all variable definitions from the modular files in
# the variables/ folder for better organization reference:
#   - variables/variables_common.tf      → Common/General configuration
#   - variables/variables_aws.tf         → AWS-specific configuration
#   - variables/variables_azure.tf       → Azure-specific configuration
#   - variables/variables_gcp.tf         → GCP-specific configuration
#   - variables/variables_compute.tf     → Compute/scaling configuration
#   - variables/variables_network.tf     → Network/VPC configuration
#   - variables/variables_scheduling.tf  → Scheduling configuration
#   - variables/variables_loadbalancer.tf → Load balancer configuration
# ==============================================================================


# ==============================================================================
# SECTION 1: Common Variables - General project configuration
# ==============================================================================
# Source: variables/variables_common.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# Region Preference Configuration
# ------------------------------------------------------------------------------
variable "preferred_region" {
  description = "Preferred region for deployment (india or us). India zones are primary, US zones are fallback."
  type        = string
  default     = "india"

  validation {
    condition     = contains(["india", "us"], var.preferred_region)
    error_message = "Preferred region must be one of: india, us."
  }
}

variable "auto_fallback_to_us" {
  description = "Automatically fallback to US region if instance type is not available in India"
  type        = bool
  default     = true
}

variable "skip_instance_check" {
  description = "Skip checking for existing instances (set to true to force creation)"
  type        = bool
  default     = false
}

variable "existing_instance_tag_filter" {
  description = "Tag key to filter existing instances by (used to check if similar instances already exist)"
  type        = string
  default     = "Project"
}

# ------------------------------------------------------------------------------
# General Configuration
# ------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "gpu-infra"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "OpenAgriNet - The Next GEN Agri Tech"
}

# ------------------------------------------------------------------------------
# Cloud Provider Selection
# ------------------------------------------------------------------------------
variable "cloud_provider" {
  description = "Cloud provider to use (aws, azure, gcp)"
  type        = string

  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Cloud provider must be one of: aws, azure, gcp."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}


# ==============================================================================
# SECTION 2: AWS Variables - AWS-specific credentials and configuration
# ==============================================================================
# Source: variables/variables_aws.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# AWS Credentials
# ------------------------------------------------------------------------------
variable "aws_account_id" {
  description = "AWS Account ID (12-digit number) or Account Alias"
  type        = string
  default     = ""

  validation {
    condition     = var.aws_account_id == "" || can(regex("^[0-9]{12}$", var.aws_account_id)) || can(regex("^[a-z][a-z0-9-]{2,62}$", var.aws_account_id))
    error_message = "AWS Account ID must be a 12-digit number or a valid account alias (3-63 lowercase alphanumeric characters or hyphens, starting with a letter)."
  }
}

variable "aws_iam_username" {
  description = "AWS IAM Username for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_iam_password" {
  description = "AWS IAM User Password (for console access reference - actual API auth uses access keys)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_access_key" {
  description = "AWS Access Key ID (generated from IAM user credentials)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key (generated from IAM user credentials)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token (required for temporary credentials/MFA)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_profile" {
  description = "AWS CLI profile name to use for authentication (alternative to access keys)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# AWS Region Configuration
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS Region (auto-selected based on preferred_region if not explicitly set)"
  type        = string
  default     = ""
}

variable "aws_availability_zones" {
  description = "List of availability zones for AWS (auto-selected based on region)"
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# AWS Instance Configuration
# ------------------------------------------------------------------------------
variable "instance_type_aws" {
  description = "AWS GPU instance type"
  type        = string
  default     = "g5.4xlarge"
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

# ------------------------------------------------------------------------------
# AWS Region Mappings (Locals)
# ------------------------------------------------------------------------------
locals {
  # AWS region mapping based on preference
  aws_region_map = {
    india = "ap-south-1"
    us    = "us-east-1"
  }

  aws_az_map = {
    india = ["ap-south-1a", "ap-south-1b"]
    us    = ["us-east-1a", "us-east-1b"]
  }

  # Computed AWS region - use explicit if provided, otherwise use preference
  computed_aws_region = var.aws_region != "" ? var.aws_region : local.aws_region_map[var.preferred_region]
  computed_aws_azs    = length(var.aws_availability_zones) > 0 ? var.aws_availability_zones : local.aws_az_map[var.preferred_region]
}


# ==============================================================================
# SECTION 3: Azure Variables - Azure-specific credentials and configuration
# ==============================================================================
# Source: variables/variables_azure.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# Azure Credentials
# Authentication Methods:
# 1. Service Principal (Client ID + Secret) - Recommended for automation
# 2. Managed Identity - For resources running in Azure
# 3. Azure CLI - For local development (az login)
# ------------------------------------------------------------------------------
variable "azure_subscription_id" {
  description = "Azure Subscription ID (GUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.azure_subscription_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.azure_subscription_id)))
    error_message = "Azure Subscription ID must be a valid GUID format."
  }
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID / Directory ID (GUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.azure_tenant_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.azure_tenant_id)))
    error_message = "Azure Tenant ID must be a valid GUID format."
  }
}

variable "azure_client_id" {
  description = "Azure Client ID / Application ID (Service Principal - GUID format)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.azure_client_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.azure_client_id)))
    error_message = "Azure Client ID must be a valid GUID format."
  }
}

variable "azure_client_secret" {
  description = "Azure Client Secret / Application Password (Service Principal secret value)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_use_msi" {
  description = "Use Managed Service Identity for authentication (when running on Azure resources)"
  type        = bool
  default     = false
}

variable "azure_use_cli" {
  description = "Use Azure CLI for authentication (requires 'az login' to be run first)"
  type        = bool
  default     = false
}

variable "azure_environment" {
  description = "Azure Environment (public, usgovernment, china, german)"
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "usgovernment", "china", "german"], var.azure_environment)
    error_message = "Azure environment must be one of: public, usgovernment, china, german."
  }
}

# ------------------------------------------------------------------------------
# Azure Region Configuration
# ------------------------------------------------------------------------------
variable "azure_location" {
  description = "Azure Region/Location (auto-selected based on preferred_region if not explicitly set)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Azure Instance Configuration
# ------------------------------------------------------------------------------
variable "instance_type_azure" {
  description = "Azure GPU instance type"
  type        = string
  default     = "Standard_NV36ads_A10_v5"
}

# ------------------------------------------------------------------------------
# Azure Region Mappings (Locals)
# ------------------------------------------------------------------------------
locals {
  azure_region_map = {
    india = "centralindia"
    us    = "eastus"
  }

  # Computed Azure region
  computed_azure_location = var.azure_location != "" ? var.azure_location : local.azure_region_map[var.preferred_region]
}


# ==============================================================================
# SECTION 4: GCP Variables - GCP-specific credentials and configuration
# ==============================================================================
# Source: variables/variables_gcp.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# GCP Credentials
# Authentication Methods:
# 1. Service Account JSON file - Recommended for automation
# 2. Service Account JSON content - For CI/CD environments
# 3. Application Default Credentials - For local development (gcloud auth)
# ------------------------------------------------------------------------------
variable "gcp_project_id" {
  description = "GCP Project ID (the unique identifier for your project, not the project number)"
  type        = string
  default     = ""

  validation {
    condition     = var.gcp_project_id == "" || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "GCP Project ID must be 6-30 lowercase letters, digits, or hyphens. It must start with a letter and cannot end with a hyphen."
  }
}

variable "gcp_project_number" {
  description = "GCP Project Number (numeric identifier, optional - for reference)"
  type        = string
  default     = ""

  validation {
    condition     = var.gcp_project_number == "" || can(regex("^[0-9]+$", var.gcp_project_number))
    error_message = "GCP Project Number must be a numeric value."
  }
}

variable "gcp_credentials_file" {
  description = "Path to GCP Service Account JSON key file"
  type        = string
  default     = ""
}

variable "gcp_credentials_json" {
  description = "GCP Service Account JSON key content (alternative to file path - useful for CI/CD)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gcp_service_account_email" {
  description = "GCP Service Account Email (format: name@project-id.iam.gserviceaccount.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.gcp_service_account_email == "" || can(regex("^[a-z][a-z0-9-]*@[a-z][a-z0-9-]*\\.iam\\.gserviceaccount\\.com$", var.gcp_service_account_email))
    error_message = "GCP Service Account Email must be in the format: name@project-id.iam.gserviceaccount.com"
  }
}

variable "gcp_impersonate_service_account" {
  description = "Service Account to impersonate for Terraform operations (optional)"
  type        = string
  default     = ""
}

variable "gcp_access_token" {
  description = "GCP OAuth2 Access Token (for temporary authentication)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gcp_use_adc" {
  description = "Use Application Default Credentials (requires 'gcloud auth application-default login')"
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# GCP Region Configuration
# ------------------------------------------------------------------------------
variable "gcp_region" {
  description = "GCP Region (auto-selected based on preferred_region if not explicitly set)"
  type        = string
  default     = ""
}

variable "gcp_zone" {
  description = "GCP Zone (auto-selected based on preferred_region if not explicitly set)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# GCP Instance Configuration
# ------------------------------------------------------------------------------
variable "machine_type_gcp" {
  description = "GCP machine type"
  type        = string
  default     = "n1-standard-16"
}

variable "gpu_type_gcp" {
  description = "GCP GPU type"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_count_gcp" {
  description = "Number of GPUs for GCP instances"
  type        = number
  default     = 1
}

# ------------------------------------------------------------------------------
# GCP Region Mappings (Locals)
# ------------------------------------------------------------------------------
locals {
  gcp_region_map = {
    india = "asia-south1"
    us    = "us-east1"
  }

  gcp_zone_map = {
    india = "asia-south1-a"
    us    = "us-east1-b"
  }

  # Computed GCP region/zone
  computed_gcp_region = var.gcp_region != "" ? var.gcp_region : local.gcp_region_map[var.preferred_region]
  computed_gcp_zone   = var.gcp_zone != "" ? var.gcp_zone : local.gcp_zone_map[var.preferred_region]
}


# ==============================================================================
# SECTION 5: Compute Variables - Instance and scaling configuration
# ==============================================================================
# Source: variables/variables_compute.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# Volume Configuration
# ------------------------------------------------------------------------------
variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

variable "root_volume_type" {
  description = "Root volume type (gp3 for AWS)"
  type        = string
  default     = "gp3"
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
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 1
}

variable "scale_up_cpu_threshold" {
  description = "CPU threshold percentage for scaling up"
  type        = number
  default     = 80
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold percentage for scaling down"
  type        = number
  default     = 20
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
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
  description = "CUDA toolkit version"
  type        = string
  default     = "12.4"
}


# ==============================================================================
# SECTION 6: Network Variables - VPC and networking configuration
# ==============================================================================
# Source: variables/variables_network.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC Configuration
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

# ------------------------------------------------------------------------------
# Access Control
# ------------------------------------------------------------------------------
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
# SSH Key Configuration
# ------------------------------------------------------------------------------
variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Name for the SSH key pair"
  type        = string
  default     = "gpu-infra-key"
}


# ==============================================================================
# SECTION 7: Scheduling Variables - Start/Stop scheduling configuration
# ==============================================================================
# Source: variables/variables_scheduling.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# Scheduling Configuration
# ------------------------------------------------------------------------------
variable "enable_scheduling" {
  description = "Enable scheduled start/stop"
  type        = bool
  default     = true
}

# IST 9:30 AM = UTC 04:00
variable "schedule_start_cron" {
  description = "Cron expression for start time (UTC)"
  type        = string
  default     = "cron(0 4 ? * MON-FRI *)"
}

# Ethiopia Time 6:00 PM = UTC 15:00
variable "schedule_stop_cron" {
  description = "Cron expression for stop time (UTC)"
  type        = string
  default     = "cron(0 15 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "Timezone for scheduling display"
  type        = string
  default     = "UTC"
}


# ==============================================================================
# SECTION 8: Load Balancer Variables - Load balancer and health check config
# ==============================================================================
# Source: variables/variables_loadbalancer.tf
# ==============================================================================

# ------------------------------------------------------------------------------
# Load Balancer Configuration
# ------------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Enable load balancer"
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 8080
}

# ------------------------------------------------------------------------------
# Health Check Configuration
# ------------------------------------------------------------------------------
variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Health check port"
  type        = number
  default     = 8080
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3
}
