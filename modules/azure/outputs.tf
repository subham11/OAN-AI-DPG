# ==============================================================================
# Azure Module Outputs
# ==============================================================================

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource group ID"
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.main.name
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = azurerm_subnet.private[*].id
}

output "vmss_id" {
  description = "VMSS ID"
  value       = azurerm_linux_virtual_machine_scale_set.gpu.id
}

output "vmss_name" {
  description = "VMSS name"
  value       = azurerm_linux_virtual_machine_scale_set.gpu.name
}

output "lb_public_ip" {
  description = "Load Balancer public IP"
  value       = var.enable_load_balancer ? azurerm_public_ip.lb[0].ip_address : null
}

output "lb_fqdn" {
  description = "Load Balancer FQDN"
  value       = var.enable_load_balancer ? azurerm_public_ip.lb[0].fqdn : null
}

output "nsg_id" {
  description = "Network Security Group ID"
  value       = azurerm_network_security_group.main.id
}
