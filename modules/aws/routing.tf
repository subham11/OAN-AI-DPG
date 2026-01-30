# ==============================================================================
# AWS Route Table Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Public Route Table (only created if not reusing existing VPC)
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  subnet_id      = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public[0].id
}

# ------------------------------------------------------------------------------
# Private Route Tables (only created if not reusing existing VPC)
# ------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = var.use_existing_vpc ? 0 : length(var.private_subnet_cidrs)

  vpc_id = local.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = var.use_existing_vpc ? 0 : length(var.private_subnet_cidrs)

  subnet_id      = local.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}
