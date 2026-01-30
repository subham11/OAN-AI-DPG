# ==============================================================================
# AWS NAT Gateway Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways (only created if not reusing existing VPC)
# ------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ------------------------------------------------------------------------------
# NAT Gateways (only created if not reusing existing VPC)
# ------------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = local.public_subnet_ids[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}
