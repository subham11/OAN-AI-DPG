# ==============================================================================
# Azure Staging Environment - Outputs
# ==============================================================================

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "resource_group_name" {
  description = "Resource Group name"
  value       = module.gpu_infrastructure.resource_group_name
}

output "vnet_id" {
  description = "Virtual Network ID"
  value       = module.gpu_infrastructure.vnet_id
}

output "vmss_id" {
  description = "Virtual Machine Scale Set ID"
  value       = module.gpu_infrastructure.vmss_id
}

output "lb_public_ip" {
  description = "Load Balancer public IP"
  value       = module.gpu_infrastructure.lb_public_ip
}

output "load_balancer_url" {
  description = "URL to access the application"
  value       = var.enable_load_balancer ? "http://${module.gpu_infrastructure.lb_public_ip}" : null
}

output "nvidia_driver_version" {
  description = "NVIDIA driver version"
  value       = var.nvidia_driver_version
}

output "cuda_version" {
  description = "CUDA version"
  value       = var.cuda_version
}
