# ==============================================================================
# Azure Module - Main Entry Point
# ==============================================================================

# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.common_tags
}

# ------------------------------------------------------------------------------
# Random suffix for unique naming
# ------------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Unique names for storage accounts (must be globally unique)
  storage_account_name = "gpuinfra${random_string.suffix.result}"
}
