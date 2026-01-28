# ==============================================================================
# Main Entry Point - Multi-Cloud GPU Infrastructure
# ==============================================================================
# This module orchestrates deployment across AWS, Azure, or GCP based on
# the selected cloud_provider variable.
# ==============================================================================

locals {
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

  # Compute naming prefix
  name_prefix = "${var.project_name}-${var.environment}"
}

# ==============================================================================
# AWS Module
# ==============================================================================
module "aws" {
  source = "./modules/aws"
  count  = var.cloud_provider == "aws" ? 1 : 0

  # General
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags

  # Network
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.aws_availability_zones
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
  allowed_http_cidrs   = var.allowed_http_cidrs

  # Compute
  instance_type      = var.instance_type_aws
  use_spot_instances = var.use_spot_instances
  spot_max_price     = var.spot_max_price
  root_volume_size   = var.root_volume_size
  root_volume_type   = var.root_volume_type
  key_name           = var.key_name
  ssh_public_key     = var.ssh_public_key

  # Auto-Scaling
  asg_min_size              = var.asg_min_size
  asg_max_size              = var.asg_max_size
  asg_desired_capacity      = var.asg_desired_capacity
  scale_up_cpu_threshold    = var.scale_up_cpu_threshold
  scale_down_cpu_threshold  = var.scale_down_cpu_threshold
  health_check_grace_period = var.health_check_grace_period

  # Load Balancer
  enable_load_balancer  = var.enable_load_balancer
  health_check_path     = var.health_check_path
  health_check_port     = var.health_check_port
  health_check_interval = var.health_check_interval
  health_check_timeout  = var.health_check_timeout
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

# ==============================================================================
# Azure Module
# ==============================================================================
module "azure" {
  source = "./modules/azure"
  count  = var.cloud_provider == "azure" ? 1 : 0

  # General
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags
  location     = var.azure_location

  # Network
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
  allowed_http_cidrs   = var.allowed_http_cidrs

  # Compute
  instance_type    = var.instance_type_azure
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

# ==============================================================================
# GCP Module
# ==============================================================================
module "gcp" {
  source = "./modules/gcp"
  count  = var.cloud_provider == "gcp" ? 1 : 0

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
  machine_type     = var.machine_type_gcp
  gpu_type         = var.gpu_type_gcp
  gpu_count        = var.gpu_count_gcp
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
