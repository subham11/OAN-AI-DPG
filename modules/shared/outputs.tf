# ==============================================================================
# Shared Outputs for DPG GPU Infrastructure
# ==============================================================================
# These outputs are available when the shared module is used.
# ==============================================================================

output "name_prefix" {
  description = "Computed name prefix for resources"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags to apply to all resources"
  value       = local.common_tags
}

output "schedule_description" {
  description = "Human-readable schedule description"
  value       = local.schedule_description
}
