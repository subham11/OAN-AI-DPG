# ==============================================================================
# AWS Staging Environment - Main Configuration
# ==============================================================================
# This is the entry point for the AWS staging environment.
# Run `terraform init` and `terraform apply` from this directory.
# ==============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ------------------------------------------------------------------------------
# AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  # Explicit credentials (if provided)
  access_key = var.aws_access_key != "" ? var.aws_access_key : null
  secret_key = var.aws_secret_key != "" ? var.aws_secret_key : null
  token      = var.aws_session_token != "" ? var.aws_session_token : null

  # Account validation
  allowed_account_ids = var.aws_account_id != "" ? [var.aws_account_id] : null

  # Note: default_tags removed to avoid iam:TagRole permission requirement
}

# ------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Note: Tags disabled to avoid iam:TagRole/TagPolicy permission requirement
  common_tags = {}
}

# ------------------------------------------------------------------------------
# AWS GPU Infrastructure Module
# ------------------------------------------------------------------------------
module "gpu_infrastructure" {
  source = "../../../modules/aws"

  # General
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags

  # Network
  use_existing_vpc            = var.use_existing_vpc
  existing_vpc_id             = var.existing_vpc_id
  existing_public_subnet_ids  = var.existing_public_subnet_ids
  existing_private_subnet_ids = var.existing_private_subnet_ids
  vpc_cidr                    = var.vpc_cidr
  public_subnet_cidrs         = var.public_subnet_cidrs
  private_subnet_cidrs        = var.private_subnet_cidrs
  availability_zones          = var.availability_zones
  allowed_ssh_cidrs           = var.allowed_ssh_cidrs
  allowed_http_cidrs   = var.allowed_http_cidrs

  # Compute
  instance_type      = var.instance_type
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
