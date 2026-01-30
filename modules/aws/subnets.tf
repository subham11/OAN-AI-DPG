# ==============================================================================
# AWS Subnet Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Data sources for existing subnets (when reusing)
# ------------------------------------------------------------------------------
data "aws_subnet" "existing_public" {
  count = var.use_existing_vpc ? length(var.existing_public_subnet_ids) : 0
  id    = var.existing_public_subnet_ids[count.index]
}

data "aws_subnet" "existing_private" {
  count = var.use_existing_vpc ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

# ------------------------------------------------------------------------------
# Public Subnets (only created if not reusing existing)
# ------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-public-${count.index + 1}"
    Type = "Public"
  })
}

# ------------------------------------------------------------------------------
# Private Subnets (only created if not reusing existing)
# ------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = var.use_existing_vpc ? 0 : length(var.private_subnet_cidrs)

  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-private-${count.index + 1}"
    Type = "Private"
  })
}

# ------------------------------------------------------------------------------
# Local values for subnet IDs (handles both new and existing)
# ------------------------------------------------------------------------------
locals {
  public_subnet_ids = var.use_existing_vpc ? var.existing_public_subnet_ids : aws_subnet.public[*].id
  private_subnet_ids = var.use_existing_vpc ? var.existing_private_subnet_ids : aws_subnet.private[*].id
  
  # Availability zones - from existing subnets or from variable
  subnet_azs = var.use_existing_vpc ? (
    length(var.existing_public_subnet_ids) > 0 ? 
      data.aws_subnet.existing_public[*].availability_zone : 
      data.aws_subnet.existing_private[*].availability_zone
  ) : var.availability_zones
  
  # ===========================================================================
  # ALB Subnet Selection - Ensure only ONE subnet per AZ
  # ===========================================================================
  # ALBs require subnets in different AZs. If multiple subnets exist in the 
  # same AZ, we select only the first one per AZ to avoid the error:
  # "A load balancer cannot be attached to multiple subnets in the same AZ"
  # ===========================================================================
  
  # Build a map of AZ -> first subnet ID for public subnets
  # This ensures only one subnet per AZ is used for the ALB
  public_subnet_az_map = var.use_existing_vpc ? {
    for idx, subnet in data.aws_subnet.existing_public : 
      subnet.availability_zone => subnet.id...
  } : {
    for idx, subnet in aws_subnet.public : 
      subnet.availability_zone => subnet.id...
  }
  
  # Get unique subnets for ALB (first subnet per AZ)
  alb_subnet_ids = [
    for az, subnet_ids in local.public_subnet_az_map : subnet_ids[0]
  ]
}
