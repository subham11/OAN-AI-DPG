# ==============================================================================
# AWS Load Balancer Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------------------------------
# Note: ALB requires subnets in different AZs. We use local.alb_subnet_ids
# which ensures only ONE subnet per AZ is used, avoiding the error:
# "A load balancer cannot be attached to multiple subnets in the same AZ"
# ------------------------------------------------------------------------------
resource "aws_lb" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.alb_subnet_ids

  enable_deletion_protection = var.environment == "prod" ? true : false
  enable_http2               = true

  # Access logs (optional - requires S3 bucket)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.bucket
  #   prefix  = "alb-logs"
  #   enabled = true
  # }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb"
  })
}

# ------------------------------------------------------------------------------
# Target Group
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name        = "${var.name_prefix}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    interval            = var.health_check_interval
    matcher             = "200-299"
    path                = var.health_check_path
    port                = var.health_check_port
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.unhealthy_threshold
  }

  # Stickiness (optional)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  # Deregistration delay
  deregistration_delay = 30

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# HTTP Listener (Redirect to HTTPS in production)
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  # For production, redirect to HTTPS
  # For development, forward to target group
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# HTTPS Listener (Uncomment when certificate is available)
# ------------------------------------------------------------------------------
# resource "aws_lb_listener" "https" {
#   count = var.enable_load_balancer ? 1 : 0
#
#   load_balancer_arn = aws_lb.main[0].arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = aws_acm_certificate.main.arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main[0].arn
#   }
#
#   tags = var.common_tags
# }

# ------------------------------------------------------------------------------
# CloudWatch Alarms for ALB
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.enable_load_balancer ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5XX errors exceeded threshold"

  dimensions = {
    LoadBalancer = aws_lb.main[0].arn_suffix
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = var.enable_load_balancer ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Target 5XX errors exceeded threshold"

  dimensions = {
    LoadBalancer = aws_lb.main[0].arn_suffix
    TargetGroup  = aws_lb_target_group.main[0].arn_suffix
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.enable_load_balancer ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Unhealthy hosts detected"

  dimensions = {
    LoadBalancer = aws_lb.main[0].arn_suffix
    TargetGroup  = aws_lb_target_group.main[0].arn_suffix
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count = var.enable_load_balancer ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "ALB response time exceeded 5 seconds"

  dimensions = {
    LoadBalancer = aws_lb.main[0].arn_suffix
    TargetGroup  = aws_lb_target_group.main[0].arn_suffix
  }

  tags = var.common_tags

  treat_missing_data = "notBreaching"
}
