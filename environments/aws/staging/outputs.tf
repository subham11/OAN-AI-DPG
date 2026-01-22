# ==============================================================================
# AWS Staging Environment - Outputs
# ==============================================================================

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.gpu_infrastructure.vpc_id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.gpu_infrastructure.asg_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.gpu_infrastructure.alb_dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer Zone ID"
  value       = module.gpu_infrastructure.alb_zone_id
}

output "scheduler_lambda_arns" {
  description = "Lambda ARNs for scheduling"
  value       = module.gpu_infrastructure.scheduler_lambda_arns
}

output "load_balancer_url" {
  description = "URL to access the application"
  value       = var.enable_load_balancer ? "http://${module.gpu_infrastructure.alb_dns_name}" : null
}

output "nvidia_driver_version" {
  description = "NVIDIA driver version"
  value       = var.nvidia_driver_version
}

output "cuda_version" {
  description = "CUDA toolkit version"
  value       = var.cuda_version
}

output "schedule_info" {
  description = "Scheduling information"
  value = var.enable_scheduling ? {
    enabled    = true
    start_time = "04:00 UTC (9:30 AM IST)"
    stop_time  = "15:00 UTC (6:00 PM Ethiopia)"
  } : { enabled = false }
}
