# ==============================================================================
# Provider Configurations
# ==============================================================================

# ------------------------------------------------------------------------------
# AWS Provider
# Supports multiple authentication methods:
# 1. Access Key + Secret Key (explicit credentials)
# 2. AWS CLI Profile
# 3. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
# 4. IAM Role (when running on AWS resources)
# ------------------------------------------------------------------------------
provider "aws" {
  region     = local.computed_aws_region
  access_key = var.aws_access_key != "" ? var.aws_access_key : null
  secret_key = var.aws_secret_key != "" ? var.aws_secret_key : null
  token      = var.aws_session_token != "" ? var.aws_session_token : null
  profile    = var.aws_profile != "" ? var.aws_profile : null

  # Account validation
  allowed_account_ids = var.aws_account_id != "" ? [var.aws_account_id] : null

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }

  # Only configure if AWS is selected
  skip_credentials_validation = var.cloud_provider != "aws"
  skip_metadata_api_check     = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
}

# ------------------------------------------------------------------------------
# Azure Provider
# Supports multiple authentication methods:
# 1. Service Principal (Client ID + Secret)
# 2. Managed Service Identity (MSI)
# 3. Azure CLI
# ------------------------------------------------------------------------------
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = true
      skip_shutdown_and_force_delete = false
    }
  }

  subscription_id = var.azure_subscription_id != "" ? var.azure_subscription_id : null
  tenant_id       = var.azure_tenant_id != "" ? var.azure_tenant_id : null
  client_id       = var.azure_client_id != "" ? var.azure_client_id : null
  client_secret   = var.azure_client_secret != "" ? var.azure_client_secret : null

  # Use MSI if specified
  use_msi = var.azure_use_msi

  # Use Azure CLI if specified (and no service principal credentials)
  use_cli = var.azure_use_cli && var.azure_client_id == ""

  # Environment configuration
  environment = var.azure_environment

  skip_provider_registration = var.cloud_provider != "azure"
}

# ------------------------------------------------------------------------------
# GCP Provider
# Supports multiple authentication methods:
# 1. Service Account JSON file
# 2. Service Account JSON content
# 3. Application Default Credentials (ADC)
# 4. Access Token
# 5. Service Account Impersonation
# ------------------------------------------------------------------------------
locals {
  # Determine GCP credentials source
  gcp_credentials = (
    var.gcp_credentials_file != "" ? file(var.gcp_credentials_file) :
    var.gcp_credentials_json != "" ? var.gcp_credentials_json :
    null
  )
}

provider "google" {
  project     = var.gcp_project_id
  region      = local.computed_gcp_region
  zone        = local.computed_gcp_zone
  credentials = local.gcp_credentials

  # Use access token if provided
  access_token = var.gcp_access_token != "" ? var.gcp_access_token : null

  # Service account impersonation
  impersonate_service_account = var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}

provider "google-beta" {
  project     = var.gcp_project_id
  region      = local.computed_gcp_region
  zone        = local.computed_gcp_zone
  credentials = local.gcp_credentials

  # Use access token if provided
  access_token = var.gcp_access_token != "" ? var.gcp_access_token : null

  # Service account impersonation
  impersonate_service_account = var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}
