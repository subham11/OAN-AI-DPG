# ==============================================================================
# AWS Scheduler Resources - Lambda + EventBridge
# ==============================================================================
# Scheduling: IST 9:30 AM (04:00 UTC) to Ethiopia Time 6:00 PM (15:00 UTC)
# ==============================================================================

# ------------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "start_lambda" {
  count = var.enable_scheduling ? 1 : 0

  name              = "/aws/lambda/${var.name_prefix}-start-instances"
  retention_in_days = 30

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "stop_lambda" {
  count = var.enable_scheduling ? 1 : 0

  name              = "/aws/lambda/${var.name_prefix}-stop-instances"
  retention_in_days = 30

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Lambda Function - Start Instances
# ------------------------------------------------------------------------------
data "archive_file" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda/start_instances.zip"

  source {
    content = templatefile("${path.module}/templates/lambda_start.py.tpl", {
      asg_name     = aws_autoscaling_group.gpu.name
      project_name = var.project_name
      environment  = var.environment
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  function_name    = "${var.name_prefix}-start-instances"
  role             = aws_iam_role.scheduler_lambda[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 128
  filename         = data.archive_file.start_instances[0].output_path
  source_code_hash = data.archive_file.start_instances[0].output_base64sha256

  environment {
    variables = {
      ASG_NAME     = aws_autoscaling_group.gpu.name
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
      LOG_LEVEL    = "INFO"
    }
  }

  tags = var.common_tags

  depends_on = [
    aws_cloudwatch_log_group.start_lambda,
    aws_iam_role_policy_attachment.scheduler_lambda_basic,
    aws_iam_role_policy_attachment.scheduler_ec2,
    aws_iam_role_policy_attachment.scheduler_logs
  ]
}

# ------------------------------------------------------------------------------
# Lambda Function - Stop Instances
# ------------------------------------------------------------------------------
data "archive_file" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda/stop_instances.zip"

  source {
    content = templatefile("${path.module}/templates/lambda_stop.py.tpl", {
      asg_name     = aws_autoscaling_group.gpu.name
      project_name = var.project_name
      environment  = var.environment
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  function_name    = "${var.name_prefix}-stop-instances"
  role             = aws_iam_role.scheduler_lambda[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 128
  filename         = data.archive_file.stop_instances[0].output_path
  source_code_hash = data.archive_file.stop_instances[0].output_base64sha256

  environment {
    variables = {
      ASG_NAME     = aws_autoscaling_group.gpu.name
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
      LOG_LEVEL    = "INFO"
    }
  }

  tags = var.common_tags

  depends_on = [
    aws_cloudwatch_log_group.stop_lambda,
    aws_iam_role_policy_attachment.scheduler_lambda_basic,
    aws_iam_role_policy_attachment.scheduler_ec2,
    aws_iam_role_policy_attachment.scheduler_logs
  ]
}

# ------------------------------------------------------------------------------
# EventBridge Rules
# ------------------------------------------------------------------------------

# Start Instances Rule - IST 9:30 AM (04:00 UTC)
resource "aws_cloudwatch_event_rule" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  name                = "${var.name_prefix}-start-instances"
  description         = "Start GPU instances at IST 9:30 AM (04:00 UTC)"
  schedule_expression = var.schedule_start_cron

  # Note: Tags removed to avoid events:TagResource permission requirement
}

resource "aws_cloudwatch_event_target" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  rule      = aws_cloudwatch_event_rule.start_instances[0].name
  target_id = "StartGPUInstances"
  arn       = aws_lambda_function.start_instances[0].arn
}

resource "aws_lambda_permission" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_instances[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instances[0].arn
}

# Stop Instances Rule - Ethiopia Time 6:00 PM (15:00 UTC)
resource "aws_cloudwatch_event_rule" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  name                = "${var.name_prefix}-stop-instances"
  description         = "Stop GPU instances at Ethiopia Time 6:00 PM (15:00 UTC)"
  schedule_expression = var.schedule_stop_cron

  # Note: Tags removed to avoid events:TagResource permission requirement
}

resource "aws_cloudwatch_event_target" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  rule      = aws_cloudwatch_event_rule.stop_instances[0].name
  target_id = "StopGPUInstances"
  arn       = aws_lambda_function.stop_instances[0].arn
}

resource "aws_lambda_permission" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instances[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instances[0].arn
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms for Lambda Errors
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "start_lambda_errors" {
  count = var.enable_scheduling ? 1 : 0

  alarm_name          = "${var.name_prefix}-start-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Start instances Lambda function errors"

  dimensions = {
    FunctionName = aws_lambda_function.start_instances[0].function_name
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "stop_lambda_errors" {
  count = var.enable_scheduling ? 1 : 0

  alarm_name          = "${var.name_prefix}-stop-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Stop instances Lambda function errors"

  dimensions = {
    FunctionName = aws_lambda_function.stop_instances[0].function_name
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}
