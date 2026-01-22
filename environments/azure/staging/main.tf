# ==============================================================================
# Azure Staging Environment - Main Configuration
# ==============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ------------------------------------------------------------------------------
# Azure Provider Configuration
# ------------------------------------------------------------------------------
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }
  }

  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id != "" ? var.azure_tenant_id : null
  client_id       = var.azure_client_id != "" ? var.azure_client_id : null
  client_secret   = var.azure_client_secret != "" ? var.azure_client_secret : null

  use_msi = var.azure_use_msi
  use_cli = var.azure_use_cli && var.azure_client_id == ""
}

# ------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      GPUEnabled  = "true"
    },
    var.additional_tags
  )
}

# ------------------------------------------------------------------------------
# Azure GPU Infrastructure Module
# ------------------------------------------------------------------------------
module "gpu_infrastructure" {
  source = "../../../modules/azure"

  # General
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags
  location     = var.location

  # Network
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
  allowed_http_cidrs   = var.allowed_http_cidrs

  # Compute
  instance_type    = var.instance_type
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
