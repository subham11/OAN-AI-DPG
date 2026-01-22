# ==============================================================================
# GCP Staging Environment - Outputs
# ==============================================================================

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.gpu_infrastructure.vpc_id
}

output "mig_name" {
  description = "Managed Instance Group name"
  value       = module.gpu_infrastructure.mig_name
}

output "lb_ip" {
  description = "Load Balancer IP"
  value       = module.gpu_infrastructure.lb_ip
}

output "load_balancer_url" {
  description = "URL to access the application"
  value       = var.enable_load_balancer ? "http://${module.gpu_infrastructure.lb_ip}" : null
}

output "nvidia_driver_version" {
  description = "NVIDIA driver version"
  value       = var.nvidia_driver_version
}

output "cuda_version" {
  description = "CUDA version"
  value       = var.cuda_version
}
