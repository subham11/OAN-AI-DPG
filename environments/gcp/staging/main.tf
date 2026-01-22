# ==============================================================================
# GCP Staging Environment - Main Configuration
# ==============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ------------------------------------------------------------------------------
# GCP Provider Configuration
# ------------------------------------------------------------------------------
locals {
  gcp_credentials = (
    var.gcp_credentials_file != "" ? file(var.gcp_credentials_file) :
    var.gcp_credentials_json != "" ? var.gcp_credentials_json :
    null
  )
}

provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  zone        = var.gcp_zone
  credentials = local.gcp_credentials

  access_token                = var.gcp_access_token != "" ? var.gcp_access_token : null
  impersonate_service_account = var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}

provider "google-beta" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  zone        = var.gcp_zone
  credentials = local.gcp_credentials

  access_token                = var.gcp_access_token != "" ? var.gcp_access_token : null
  impersonate_service_account = var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}

# ------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
      owner       = var.owner
      gpu_enabled = "true"
    },
    var.additional_tags
  )
}

# ------------------------------------------------------------------------------
# GCP GPU Infrastructure Module
# ------------------------------------------------------------------------------
module "gpu_infrastructure" {
  source = "../../../modules/gcp"

  # General
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags
  region       = var.gcp_region
  zone         = var.gcp_zone
  project_id   = var.gcp_project_id

  # Network
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
  allowed_http_cidrs   = var.allowed_http_cidrs

  # Compute
  machine_type     = var.machine_type
  gpu_type         = var.gpu_type
  gpu_count        = var.gpu_count
  root_volume_size = var.root_volume_size
  ssh_public_key   = var.ssh_public_key

  # Auto-Scaling
  asg_min_size             = var.asg_min_size
  asg_max_size             = var.asg_max_size
  asg_desired_capacity     = var.asg_desired_capacity
  scale_up_cpu_threshold   = var.scale_up_cpu_threshold
  scale_down_cpu_threshold = var.scale_down_cpu_threshold

  # Load Balancer
  enable_load_balancer  = var.enable_load_balancer
  health_check_path     = var.health_check_path
  health_check_port     = var.health_check_port
  health_check_interval = var.health_check_interval
  healthy_threshold     = var.healthy_threshold
  unhealthy_threshold   = var.unhealthy_threshold
  app_port              = var.app_port

  # NVIDIA
  nvidia_driver_version = var.nvidia_driver_version
  cuda_version          = var.cuda_version

  # Scheduling
  enable_scheduling   = var.enable_scheduling
  schedule_start_cron = var.schedule_start_cron
  schedule_stop_cron  = var.schedule_stop_cron
}
