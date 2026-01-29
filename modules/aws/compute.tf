# ==============================================================================
# AWS Compute Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# IAM Role for EC2 Instances
# ------------------------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name = "${var.name_prefix}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.instance.name

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Launch Template for GPU Instances
# ------------------------------------------------------------------------------
resource "aws_launch_template" "gpu" {
  name_prefix   = "${var.name_prefix}-gpu-"
  image_id      = data.aws_ami.gpu_ami.id
  instance_type = var.instance_type

  # Key pair for SSH access
  key_name = var.ssh_public_key != "" ? aws_key_pair.main[0].key_name : null

  # IAM Instance Profile
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # Spot instance configuration (only when use_spot_instances is true)
  # Note: ASG only supports 'one-time' spot instance type with 'terminate' behavior
  dynamic "instance_market_options" {
    for_each = var.use_spot_instances ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  # Network configuration
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.instance.id]
    delete_on_termination       = true
  }

  # Block device mapping
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }

  # User data for NVIDIA setup and health check
  user_data = base64encode(local.user_data)

  # Metadata options
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Monitoring
  monitoring {
    enabled = true
  }

  # Tags for instances
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name        = "${var.name_prefix}-gpu-instance"
      GPUInstance = "true"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-gpu-volume"
    })
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-gpu-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# Auto Scaling Group
# ------------------------------------------------------------------------------
resource "aws_autoscaling_group" "gpu" {
  name                      = "${var.name_prefix}-gpu-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.enable_load_balancer ? "ELB" : "EC2"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = var.enable_load_balancer ? [aws_lb_target_group.main[0].arn] : []

  launch_template {
    id      = aws_launch_template.gpu.id
    version = "$Latest"
  }

  # Instance refresh for updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Termination policies
  termination_policies = ["OldestInstance", "Default"]

  # Tags
  dynamic "tag" {
    for_each = merge(var.common_tags, {
      Name        = "${var.name_prefix}-gpu-instance"
      GPUInstance = "true"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ------------------------------------------------------------------------------
# Auto Scaling Policies
# ------------------------------------------------------------------------------

# Scale Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name_prefix}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.gpu.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

# Scale Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name_prefix}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.gpu.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

# CloudWatch Alarm for Scale Up
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_up_cpu_threshold
  alarm_description   = "Scale up when CPU exceeds ${var.scale_up_cpu_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.gpu.name
  }

  tags = var.common_tags
}

# CloudWatch Alarm for Scale Down
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name_prefix}-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_down_cpu_threshold
  alarm_description   = "Scale down when CPU falls below ${var.scale_down_cpu_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.gpu.name
  }

  tags = var.common_tags
}

# GPU Utilization Monitoring (Custom metric)
resource "aws_cloudwatch_metric_alarm" "gpu_memory" {
  alarm_name          = "${var.name_prefix}-gpu-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "GPUMemoryUtilization"
  namespace           = "Custom/GPU"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alert when GPU memory exceeds 90%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.gpu.name
  }

  tags = var.common_tags

  # This alarm won't trigger until custom metrics are published
  treat_missing_data = "notBreaching"
}
