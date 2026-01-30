# ==============================================================================
# AWS VPC Flow Logs
# ==============================================================================

# ------------------------------------------------------------------------------
# CloudWatch Log Group for VPC Flow Logs
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.name_prefix}-flow-logs"
  retention_in_days = 7

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# IAM Role for VPC Flow Logs
# ------------------------------------------------------------------------------
resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# VPC Flow Log
# ------------------------------------------------------------------------------
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = local.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc-flow-log"
  })
}
