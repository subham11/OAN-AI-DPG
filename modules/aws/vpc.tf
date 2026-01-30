# ==============================================================================
# AWS VPC Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Data source for existing VPC (when reusing)
# ------------------------------------------------------------------------------
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_internet_gateway" "existing" {
  count = var.use_existing_vpc ? 1 : 0

  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

# ------------------------------------------------------------------------------
# VPC (only created if not reusing existing)
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# ------------------------------------------------------------------------------
# Internet Gateway (only created if not reusing existing)
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# ------------------------------------------------------------------------------
# Local values for VPC/IGW IDs (handles both new and existing)
# ------------------------------------------------------------------------------
locals {
  vpc_id = var.use_existing_vpc ? var.existing_vpc_id : aws_vpc.main[0].id
  igw_id = var.use_existing_vpc ? data.aws_internet_gateway.existing[0].id : aws_internet_gateway.main[0].id
}
