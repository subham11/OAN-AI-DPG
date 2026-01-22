# ==============================================================================
# AWS Module Outputs
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC Outputs
# ------------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# ------------------------------------------------------------------------------
# Security Group Outputs
# ------------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "instance_security_group_id" {
  description = "Instance security group ID"
  value       = aws_security_group.instance.id
}

# ------------------------------------------------------------------------------
# Compute Outputs
# ------------------------------------------------------------------------------
output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.gpu.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.gpu.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.gpu.arn
}

# ------------------------------------------------------------------------------
# Load Balancer Outputs
# ------------------------------------------------------------------------------
output "alb_arn" {
  description = "ALB ARN"
  value       = var.enable_load_balancer ? aws_lb.main[0].arn : null
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.enable_load_balancer ? aws_lb.main[0].dns_name : null
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = var.enable_load_balancer ? aws_lb.main[0].zone_id : null
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = var.enable_load_balancer ? aws_lb_target_group.main[0].arn : null
}

# ------------------------------------------------------------------------------
# Scheduler Outputs
# ------------------------------------------------------------------------------
output "scheduler_lambda_arns" {
  description = "Lambda function ARNs for scheduling"
  value = var.enable_scheduling ? {
    start = aws_lambda_function.start_instances[0].arn
    stop  = aws_lambda_function.stop_instances[0].arn
  } : null
}

output "scheduler_eventbridge_rules" {
  description = "EventBridge rule ARNs"
  value = var.enable_scheduling ? {
    start = aws_cloudwatch_event_rule.start_instances[0].arn
    stop  = aws_cloudwatch_event_rule.stop_instances[0].arn
  } : null
}

# ------------------------------------------------------------------------------
# AMI Information
# ------------------------------------------------------------------------------
output "ami_id" {
  description = "AMI ID used for instances"
  value       = data.aws_ami.gpu_ami.id
}

output "ami_name" {
  description = "AMI name"
  value       = data.aws_ami.gpu_ami.name
}
