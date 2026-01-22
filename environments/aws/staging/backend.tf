# ==============================================================================
# AWS Staging Environment - Backend Configuration
# ==============================================================================
# Uncomment and configure for remote state storage
# ==============================================================================

# terraform {
#   backend "s3" {
#     bucket         = "dpg-terraform-state"
#     key            = "aws/staging/terraform.tfstate"
#     region         = "ap-south-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }
