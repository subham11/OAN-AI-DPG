# ==============================================================================
# Shared Locals for DPG GPU Infrastructure
# ==============================================================================
# Common computed values used across all cloud providers.
# ==============================================================================

locals {
  # Naming prefix for all resources
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags applied to all resources
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

  # Scheduling description for outputs
  schedule_description = var.enable_scheduling ? {
    start = "04:00 UTC (9:30 AM IST)"
    stop  = "15:00 UTC (6:00 PM Ethiopia Time)"
  } : null
}
