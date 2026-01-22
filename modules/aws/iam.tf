# ==============================================================================
# AWS IAM Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# IAM Role for Lambda Scheduler (Least Privilege)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "scheduler_lambda" {
  count = var.enable_scheduling ? 1 : 0

  name = "${var.name_prefix}-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Lambda Basic Execution Policy
resource "aws_iam_role_policy_attachment" "scheduler_lambda_basic" {
  count = var.enable_scheduling ? 1 : 0

  role       = aws_iam_role.scheduler_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least Privilege Policy for EC2 Instance Management
resource "aws_iam_policy" "scheduler_ec2" {
  count = var.enable_scheduling ? 1 : 0

  name        = "${var.name_prefix}-scheduler-ec2-policy"
  description = "Least privilege policy for starting/stopping G5 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "StartStopInstances"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project"     = var.project_name
            "ec2:ResourceTag/Environment" = var.environment
            "ec2:ResourceTag/GPUInstance" = "true"
          }
        }
      },
      {
        Sid    = "AutoScalingDescribe"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScalingUpdate"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = aws_autoscaling_group.gpu.arn
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "scheduler_ec2" {
  count = var.enable_scheduling ? 1 : 0

  role       = aws_iam_role.scheduler_lambda[0].name
  policy_arn = aws_iam_policy.scheduler_ec2[0].arn
}

# CloudWatch Logs Policy for Lambda
resource "aws_iam_policy" "scheduler_logs" {
  count = var.enable_scheduling ? 1 : 0

  name        = "${var.name_prefix}-scheduler-logs-policy"
  description = "Policy for Lambda to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "scheduler_logs" {
  count = var.enable_scheduling ? 1 : 0

  role       = aws_iam_role.scheduler_lambda[0].name
  policy_arn = aws_iam_policy.scheduler_logs[0].arn
}
