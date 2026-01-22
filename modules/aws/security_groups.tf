# ==============================================================================
# AWS Security Group Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Security Group - ALB
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  # HTTPS
  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  # Egress to instances
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

# ------------------------------------------------------------------------------
# Security Group - GPU Instances
# ------------------------------------------------------------------------------
resource "aws_security_group" "instance" {
  name        = "${var.name_prefix}-instance-sg"
  description = "Security group for GPU instances"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Application port from ALB (covers both app and health check if same port)
  ingress {
    description     = "Application and health check port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Health check port from ALB (only if different from app_port)
  dynamic "ingress" {
    for_each = var.health_check_port != var.app_port ? [1] : []
    content {
      description     = "Health check port from ALB"
      from_port       = var.health_check_port
      to_port         = var.health_check_port
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-instance-sg"
  })
}
