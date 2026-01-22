# ==============================================================================
# Root Outputs
# ==============================================================================

# ------------------------------------------------------------------------------
# General Outputs
# ------------------------------------------------------------------------------
output "cloud_provider" {
  description = "Selected cloud provider"
  value       = var.cloud_provider
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# ------------------------------------------------------------------------------
# AWS Outputs
# ------------------------------------------------------------------------------
output "aws_vpc_id" {
  description = "AWS VPC ID"
  value       = var.cloud_provider == "aws" ? module.aws[0].vpc_id : null
}

output "aws_asg_name" {
  description = "AWS Auto Scaling Group name"
  value       = var.cloud_provider == "aws" ? module.aws[0].asg_name : null
}

output "aws_alb_dns_name" {
  description = "AWS ALB DNS name"
  value       = var.cloud_provider == "aws" ? module.aws[0].alb_dns_name : null
}

output "aws_alb_zone_id" {
  description = "AWS ALB Zone ID"
  value       = var.cloud_provider == "aws" ? module.aws[0].alb_zone_id : null
}

output "aws_scheduler_lambda_arns" {
  description = "AWS Lambda ARNs for scheduling"
  value       = var.cloud_provider == "aws" ? module.aws[0].scheduler_lambda_arns : null
}

# ------------------------------------------------------------------------------
# Azure Outputs
# ------------------------------------------------------------------------------
output "azure_resource_group_name" {
  description = "Azure Resource Group name"
  value       = var.cloud_provider == "azure" ? module.azure[0].resource_group_name : null
}

output "azure_vnet_id" {
  description = "Azure VNet ID"
  value       = var.cloud_provider == "azure" ? module.azure[0].vnet_id : null
}

output "azure_vmss_id" {
  description = "Azure VMSS ID"
  value       = var.cloud_provider == "azure" ? module.azure[0].vmss_id : null
}

output "azure_lb_ip" {
  description = "Azure Load Balancer public IP"
  value       = var.cloud_provider == "azure" ? module.azure[0].lb_public_ip : null
}

# ------------------------------------------------------------------------------
# GCP Outputs
# ------------------------------------------------------------------------------
output "gcp_vpc_id" {
  description = "GCP VPC ID"
  value       = var.cloud_provider == "gcp" ? module.gcp[0].vpc_id : null
}

output "gcp_mig_name" {
  description = "GCP Managed Instance Group name"
  value       = var.cloud_provider == "gcp" ? module.gcp[0].mig_name : null
}

output "gcp_lb_ip" {
  description = "GCP Load Balancer IP"
  value       = var.cloud_provider == "gcp" ? module.gcp[0].lb_ip : null
}

# ------------------------------------------------------------------------------
# Scheduling Outputs
# ------------------------------------------------------------------------------
output "schedule_start_time" {
  description = "Scheduled start time (UTC)"
  value       = "04:00 UTC (9:30 AM IST)"
}

output "schedule_stop_time" {
  description = "Scheduled stop time (UTC)"
  value       = "15:00 UTC (6:00 PM Ethiopia Time)"
}

output "scheduling_enabled" {
  description = "Whether scheduling is enabled"
  value       = var.enable_scheduling
}

# ------------------------------------------------------------------------------
# Connection Information
# ------------------------------------------------------------------------------
output "load_balancer_url" {
  description = "Load balancer URL for accessing the application"
  value = var.cloud_provider == "aws" ? (
    var.enable_load_balancer ? "http://${module.aws[0].alb_dns_name}" : null
    ) : var.cloud_provider == "azure" ? (
    var.enable_load_balancer ? "http://${module.azure[0].lb_public_ip}" : null
    ) : var.cloud_provider == "gcp" ? (
    var.enable_load_balancer ? "http://${module.gcp[0].lb_ip}" : null
  ) : null
}

output "ssh_connection_info" {
  description = "SSH connection information"
  value       = "Use the bastion host or direct IP (if public) with key: ${var.key_name}"
}

# ------------------------------------------------------------------------------
# NVIDIA Configuration Outputs
# ------------------------------------------------------------------------------
output "nvidia_driver_version" {
  description = "NVIDIA driver version installed"
  value       = var.nvidia_driver_version
}

output "cuda_version" {
  description = "CUDA toolkit version installed"
  value       = var.cuda_version
}
