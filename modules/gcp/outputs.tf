# ==============================================================================
# GCP Module Outputs
# ==============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = google_compute_network.main.id
}

output "vpc_name" {
  description = "VPC name"
  value       = google_compute_network.main.name
}

output "vpc_self_link" {
  description = "VPC self link"
  value       = google_compute_network.main.self_link
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = google_compute_subnetwork.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = google_compute_subnetwork.private[*].id
}

output "mig_name" {
  description = "Managed Instance Group name"
  value       = google_compute_region_instance_group_manager.gpu.name
}

output "mig_self_link" {
  description = "Managed Instance Group self link"
  value       = google_compute_region_instance_group_manager.gpu.self_link
}

output "instance_template_self_link" {
  description = "Instance template self link"
  value       = google_compute_instance_template.gpu.self_link
}

output "lb_ip" {
  description = "Load Balancer IP address"
  value       = var.enable_load_balancer ? google_compute_global_address.lb[0].address : null
}

output "lb_name" {
  description = "Load Balancer name"
  value       = var.enable_load_balancer ? google_compute_global_forwarding_rule.http[0].name : null
}

output "firewall_rules" {
  description = "Created firewall rule names"
  value = {
    allow_ssh          = google_compute_firewall.allow_ssh.name
    allow_http         = google_compute_firewall.allow_http.name
    allow_https        = google_compute_firewall.allow_https.name
    allow_health_check = google_compute_firewall.allow_health_check.name
  }
}
