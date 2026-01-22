# ==============================================================================
# Provider Configurations for Multi-Cloud GPU Infrastructure
# ==============================================================================
# This configuration supports AWS, Azure, and GCP.
# Only the selected cloud_provider will actually be used for deployments.
# Other providers use stub/skip configurations to avoid authentication errors.
# ==============================================================================

# ------------------------------------------------------------------------------
# AWS Provider (Primary)
# ------------------------------------------------------------------------------
provider "aws" {
  region     = local.computed_aws_region
  access_key = var.aws_access_key != "" ? var.aws_access_key : null
  secret_key = var.aws_secret_key != "" ? var.aws_secret_key : null
  token      = var.aws_session_token != "" ? var.aws_session_token : null
  profile    = var.aws_profile != "" ? var.aws_profile : null

  allowed_account_ids = var.aws_account_id != "" ? [var.aws_account_id] : null

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }

  skip_credentials_validation = var.cloud_provider != "aws"
  skip_metadata_api_check     = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
}

# ------------------------------------------------------------------------------
# Azure Provider
# Uses environment variables ARM_* for authentication when Azure is selected.
# When not selected, the deploy.sh script sets up mock environment to bypass auth.
# ------------------------------------------------------------------------------
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }
  }

  # Use environment variables for all authentication
  # The deploy.sh script sets appropriate vars based on cloud_provider
  
  environment = var.azure_environment

  # Disable all resource provider registrations
  resource_provider_registrations = "none"
}

# ------------------------------------------------------------------------------
# GCP Provider (Stub when not selected)
# ------------------------------------------------------------------------------
locals {
  gcp_credentials_content = (
    var.gcp_credentials_file != "" ? file(var.gcp_credentials_file) :
    var.gcp_credentials_json != "" ? var.gcp_credentials_json :
    null
  )
  
  # Use a minimal dummy credential JSON when GCP is not selected
  gcp_stub_credentials = jsonencode({
    "type" : "service_account",
    "project_id" : "placeholder-project",
    "private_key_id" : "placeholder",
    "private_key" : "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBALRiMLAHudeSA2xnISDNQ0r9J5x8Sqr7VuK95wKPiRWRbHB4LOXC\njxzP6GN2xqSJrPyv8F2yT6P3VlK2tIHJywECAwEAAQJAYPFIW8sNJajpvIf+O4wP\nmWZQ2e7M+L6fJuJxZ6g6VZlRU9BXPnUh7vT9xP0b7YIBW6Q8WCAdO4fjH8K7NZ4J\nAQIhANqL8VNfAKf5LlfP7w2LgQB0Qp8CJPqV8sL1SgAl1jq/AiEA1CG9+6q3rRzK\n8RwBzZfz3MMSmVgH0JjVmJCKlmB+RcsCIEgNZQ7tJBh7lBzYJjz8oGd6CvvLJmg8\n+JLxZ5PIHF8hAiEAmYDHFQRlKR7VyXwJJmnJb+8F8pEhoNCrPwAnM9O0T7sCIGKB\nvfeJOxl6jj5V2fg0Nl2a7c9ecqQzP6M4FJ8qEuNX\n-----END RSA PRIVATE KEY-----\n",
    "client_email" : "placeholder@placeholder-project.iam.gserviceaccount.com",
    "client_id" : "000000000000000000000",
    "auth_uri" : "https://accounts.google.com/o/oauth2/auth",
    "token_uri" : "https://oauth2.googleapis.com/token"
  })
}

provider "google" {
  project = var.cloud_provider == "gcp" ? var.gcp_project_id : "placeholder-project"
  region  = local.computed_gcp_region
  zone    = local.computed_gcp_zone
  
  # Use actual credentials for GCP, stub for others
  credentials = var.cloud_provider == "gcp" ? local.gcp_credentials_content : local.gcp_stub_credentials

  access_token = var.cloud_provider == "gcp" && var.gcp_access_token != "" ? var.gcp_access_token : null
  impersonate_service_account = var.cloud_provider == "gcp" && var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}

provider "google-beta" {
  project = var.cloud_provider == "gcp" ? var.gcp_project_id : "placeholder-project"
  region  = local.computed_gcp_region
  zone    = local.computed_gcp_zone
  
  # Use actual credentials for GCP, stub for others
  credentials = var.cloud_provider == "gcp" ? local.gcp_credentials_content : local.gcp_stub_credentials

  access_token = var.cloud_provider == "gcp" && var.gcp_access_token != "" ? var.gcp_access_token : null
  impersonate_service_account = var.cloud_provider == "gcp" && var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}
