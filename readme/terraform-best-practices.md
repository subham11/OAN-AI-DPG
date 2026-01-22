# Terraform Best Practices & Design Patterns Guide

## Table of Contents
1. [Core Principles](#core-principles)
2. [Project Structure](#project-structure)
3. [Module Design Patterns](#module-design-patterns)
4. [State Management](#state-management)
5. [Security Best Practices](#security-best-practices)
6. [Code Quality & Standards](#code-quality--standards)
7. [Testing Strategies](#testing-strategies)
8. [CI/CD Integration](#cicd-integration)
9. [Advanced Patterns](#advanced-patterns)
10. [Tools & Ecosystem](#tools--ecosystem)

---

## Core Principles

### 1. Infrastructure as Code (IaC) Fundamentals

```
┌─────────────────────────────────────────────────────────────────┐
│                    IaC Pyramid of Best Practices                │
├─────────────────────────────────────────────────────────────────┤
│                         Policy as Code                          │
│                    ┌───────────────────────┐                    │
│               Testing & Validation                              │
│              ┌─────────────────────────────────┐                │
│         Security & Secrets Management                           │
│        ┌─────────────────────────────────────────────┐          │
│      State Management & Remote Backends                         │
│    ┌───────────────────────────────────────────────────────┐    │
│  Modularization & Code Organization                             │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ Version Control & GitOps                                        │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Key Terraform Principles

| Principle | Description |
|-----------|-------------|
| **Declarative** | Describe desired state, not steps to achieve it |
| **Idempotent** | Same configuration produces same result every time |
| **Immutable** | Replace resources rather than modify in place |
| **Versioned** | All configurations in version control |
| **Modular** | Break infrastructure into reusable components |

---

## Project Structure

### Standard Module Structure

```
terraform-project/
├── main.tf                 # Primary resource definitions
├── variables.tf            # Input variable declarations
├── outputs.tf              # Output value declarations
├── versions.tf             # Provider & Terraform version constraints
├── providers.tf            # Provider configurations
├── locals.tf               # Local value definitions
├── data.tf                 # Data source definitions
├── README.md               # Module documentation
├── CHANGELOG.md            # Version history
├── LICENSE                 # License file
├── .gitignore              # Git ignore rules
├── .terraform.lock.hcl     # Dependency lock file (commit this!)
│
├── modules/                # Child/nested modules
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/
│   └── database/
│
├── environments/           # Environment-specific configs
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   └── prod/
│
├── examples/               # Example usage
│   └── complete/
│
└── tests/                  # Test configurations
    ├── unit/
    └── integration/
```

### File Organization Best Practices

```hcl
# ============================================
# versions.tf - Always pin versions
# ============================================
terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Allows 5.x but not 6.0
    }
  }
}

# ============================================
# variables.tf - Well-documented variables
# ============================================
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_config" {
  description = "EC2 instance configuration"
  type = object({
    instance_type = string
    volume_size   = number
    encrypted     = optional(bool, true)
  })
  default = {
    instance_type = "t3.medium"
    volume_size   = 50
    encrypted     = true
  }
}

# ============================================
# locals.tf - Computed values
# ============================================
locals {
  name_prefix = "${var.project}-${var.environment}"
  
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
  
  # Merge common tags with resource-specific tags
  all_tags = merge(local.common_tags, var.additional_tags)
}
```

---

## Module Design Patterns

### Pattern 1: Facade Pattern (Simplified Interface)

Create high-level modules that orchestrate multiple complex modules:

```hcl
# modules/web-application/main.tf
# Facade module that composes multiple modules

module "networking" {
  source = "../networking"
  
  vpc_cidr     = var.vpc_cidr
  environment  = var.environment
}

module "compute" {
  source = "../compute"
  
  subnet_ids     = module.networking.private_subnet_ids
  instance_type  = var.instance_type
  instance_count = var.instance_count
}

module "database" {
  source = "../database"
  
  subnet_ids        = module.networking.database_subnet_ids
  security_group_id = module.networking.db_security_group_id
}

module "load_balancer" {
  source = "../load-balancer"
  
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  target_instances  = module.compute.instance_ids
}
```

### Pattern 2: Dependency Inversion

Pass dependencies as inputs rather than creating them internally:

```hcl
# BAD: Module creates its own VPC
module "app" {
  source = "./modules/app"
  # Module internally creates VPC - hard to share
}

# GOOD: Module receives VPC as input
module "app" {
  source = "./modules/app"
  
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.subnet_ids
}
```

### Pattern 3: Data-Only Modules

Modules that only read existing infrastructure:

```hcl
# modules/data-network/main.tf
# Reads existing network infrastructure

data "aws_vpc" "main" {
  tags = {
    Name = "${var.environment}-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  
  tags = {
    Type = "private"
  }
}

output "vpc_id" {
  value = data.aws_vpc.main.id
}

output "private_subnet_ids" {
  value = data.aws_subnets.private.ids
}
```

### Pattern 4: Conditional Resource Creation

```hcl
variable "create_load_balancer" {
  description = "Whether to create the load balancer"
  type        = bool
  default     = true
}

resource "aws_lb" "main" {
  count = var.create_load_balancer ? 1 : 0
  
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
}

# Reference conditionally created resources
output "lb_dns_name" {
  value = var.create_load_balancer ? aws_lb.main[0].dns_name : null
}
```

### Pattern 5: For_Each for Multiple Similar Resources

```hcl
variable "environments" {
  type = map(object({
    instance_type = string
    instance_count = number
  }))
  default = {
    dev = {
      instance_type  = "t3.small"
      instance_count = 1
    }
    prod = {
      instance_type  = "t3.large"
      instance_count = 3
    }
  }
}

resource "aws_instance" "app" {
  for_each = var.environments
  
  ami           = data.aws_ami.ubuntu.id
  instance_type = each.value.instance_type
  
  tags = {
    Name        = "${each.key}-app-server"
    Environment = each.key
  }
}
```

---

## State Management

### Remote State Configuration

```hcl
# backend.tf - S3 Backend with DynamoDB Locking
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Assume role for cross-account access
    role_arn = "arn:aws:iam::123456789:role/TerraformStateAccess"
  }
}
```

### State Isolation Strategies

```
┌─────────────────────────────────────────────────────────────────┐
│                    State Isolation Approaches                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Directory-Based (Recommended for most cases)                │
│     environments/                                               │
│     ├── dev/terraform.tfstate                                   │
│     ├── staging/terraform.tfstate                               │
│     └── prod/terraform.tfstate                                  │
│                                                                 │
│  2. Workspace-Based (Good for similar environments)             │
│     terraform workspace select dev                              │
│     terraform workspace select prod                             │
│                                                                 │
│  3. Composition Layers (Enterprise scale)                       │
│     networking/terraform.tfstate  (VPC, Subnets)                │
│     compute/terraform.tfstate     (EC2, ASG)                    │
│     data/terraform.tfstate        (RDS, DynamoDB)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Cross-State References

```hcl
# Read outputs from another state file
data "terraform_remote_state" "networking" {
  backend = "s3"
  
  config = {
    bucket = "company-terraform-state"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}

# Use the outputs
resource "aws_instance" "app" {
  subnet_id = data.terraform_remote_state.networking.outputs.private_subnet_ids[0]
}
```

---

## Security Best Practices

### 1. Never Commit Secrets

```hcl
# BAD - Never do this!
provider "aws" {
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

# GOOD - Use environment variables
provider "aws" {
  # Uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment
  region = var.aws_region
}

# GOOD - Use IAM roles (best practice)
provider "aws" {
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::ACCOUNT_ID:role/TerraformRole"
  }
}
```

### 2. Sensitive Variables

```hcl
variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true  # Prevents display in logs
}

# Use data sources for secrets
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/database/password"
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
}
```

### 3. Encryption & Security Groups

```hcl
# Always encrypt at rest
resource "aws_ebs_volume" "data" {
  encrypted = true
  kms_key_id = aws_kms_key.ebs.arn
}

# Principle of least privilege for security groups
resource "aws_security_group" "app" {
  name = "${local.name_prefix}-app-sg"
  
  # Specific ports, not 0-65535
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # Not 0.0.0.0/0
  }
  
  # Explicit egress (don't rely on default)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## Code Quality & Standards

### Naming Conventions

```hcl
# Resource naming pattern: {project}-{environment}-{resource}-{identifier}
locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_vpc" "main" {
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)
  
  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
  }
}
```

### Variable Naming & Documentation

```hcl
# Use descriptive names with clear types
variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (1-35)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}
```

### Formatting & Linting

```bash
# Auto-format all files
terraform fmt -recursive

# Validate configuration
terraform validate

# Use pre-commit hooks
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_docs
```

---

## Testing Strategies

### Testing Pyramid

```
                    ┌─────────────┐
                    │ End-to-End  │  ← Full deployment tests
                    │   Tests     │    (expensive, slow)
                   ┌┴─────────────┴┐
                   │  Integration  │  ← Module interaction tests
                   │    Tests      │    (Terratest, Kitchen)
                  ┌┴───────────────┴┐
                  │   Unit Tests    │  ← Static analysis
                  │                 │    (tflint, checkov)
                 ┌┴─────────────────┴┐
                 │   Validation      │  ← terraform validate
                 │   & Formatting    │    terraform fmt
                └───────────────────┘
```

### Static Analysis Tools

```bash
# TFLint - Terraform linter
tflint --init
tflint --recursive

# Checkov - Security scanner
checkov -d . --framework terraform

# tfsec - Security focused
tfsec .

# Terrascan - Compliance scanner
terrascan scan -t aws
```

### Integration Testing with Terratest

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCModule(t *testing.T) {
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/vpc",
        Vars: map[string]interface{}{
            "vpc_cidr":    "10.0.0.0/16",
            "environment": "test",
        },
    })

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcId := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcId)
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/terraform.yml
name: Terraform CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  TF_VERSION: "1.6.0"
  AWS_REGION: "us-east-1"

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Terraform Format Check
        run: terraform fmt -check -recursive
      
      - name: Terraform Init
        run: terraform init -backend=false
      
      - name: Terraform Validate
        run: terraform validate

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform

  plan:
    needs: [validate, security]
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Terraform Plan
        run: |
          terraform init
          terraform plan -out=tfplan
      
      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan

  apply:
    needs: [plan]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
      
      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
```

---

## Advanced Patterns

### Pattern 1: Dynamic Blocks

```hcl
variable "ingress_rules" {
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS"
    },
    {
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP"
    }
  ]
}

resource "aws_security_group" "web" {
  name = "web-sg"
  
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
}
```

### Pattern 2: Moved Blocks (Refactoring)

```hcl
# Refactor without destroying resources
moved {
  from = aws_instance.app
  to   = module.compute.aws_instance.app
}

moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["primary"]
}
```

### Pattern 3: Import Blocks (Terraform 1.5+)

```hcl
# Import existing resources declaratively
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "existing" {
  ami           = "ami-12345678"
  instance_type = "t3.medium"
  # ... configure to match existing resource
}
```

### Pattern 4: Check Blocks (Terraform 1.5+)

```hcl
# Validate infrastructure outside normal resource lifecycle
check "health_check" {
  data "http" "app_health" {
    url = "https://${aws_lb.main.dns_name}/health"
  }

  assert {
    condition     = data.http.app_health.status_code == 200
    error_message = "Application health check failed"
  }
}
```

### Pattern 5: Override Files

```hcl
# override.tf - Local development overrides (don't commit!)
# Automatically merged with main configuration

provider "aws" {
  region = "us-west-2"  # Override region for local testing
  
  default_tags {
    tags = {
      Developer = "local"
    }
  }
}
```

---

## Tools & Ecosystem

### Essential Tools

| Tool | Purpose | Command |
|------|---------|---------|
| **terraform fmt** | Code formatting | `terraform fmt -recursive` |
| **terraform validate** | Syntax validation | `terraform validate` |
| **TFLint** | Linting & best practices | `tflint --recursive` |
| **Checkov** | Security scanning | `checkov -d .` |
| **tfsec** | Security analysis | `tfsec .` |
| **Terrascan** | Compliance scanning | `terrascan scan` |
| **terraform-docs** | Documentation generation | `terraform-docs .` |
| **Terratest** | Integration testing | Go test framework |
| **Infracost** | Cost estimation | `infracost breakdown` |

### Wrapper Tools

| Tool | Purpose |
|------|---------|
| **Terragrunt** | DRY configurations, orchestration |
| **Atlantis** | Pull request automation |
| **Spacelift** | Terraform CI/CD platform |
| **HCP Terraform** | HashiCorp's managed service |
| **env0** | Environment as a Service |

### terraform-docs Example

```bash
# Generate README from module
terraform-docs markdown table . > README.md

# Configuration: .terraform-docs.yml
formatter: markdown table
header-from: main.tf
sort:
  enabled: true
  by: required

output:
  file: README.md
  mode: inject
```

---

## Quick Reference Checklist

### Before Every Commit
- [ ] `terraform fmt -recursive`
- [ ] `terraform validate`
- [ ] `tflint`
- [ ] Security scan (checkov/tfsec)
- [ ] Update documentation

### Module Publishing Checklist
- [ ] README.md with examples
- [ ] CHANGELOG.md updated
- [ ] All variables documented
- [ ] All outputs documented
- [ ] Version constraints defined
- [ ] Examples in /examples directory
- [ ] Tests passing

### Production Deployment Checklist
- [ ] Remote state configured
- [ ] State locking enabled
- [ ] Encryption at rest enabled
- [ ] Secrets in secrets manager
- [ ] CI/CD pipeline configured
- [ ] Rollback plan documented
- [ ] Monitoring/alerting configured

---

## Summary

The key to successful Terraform usage is:

1. **Start Simple** - Don't over-engineer initially
2. **Modularize Gradually** - Extract patterns as they emerge
3. **Version Everything** - Code, modules, and providers
4. **Automate Testing** - Static analysis and integration tests
5. **Secure by Default** - Encryption, least privilege, no secrets in code
6. **Document Thoroughly** - Future you will thank you

Remember: Terraform configurations are code. Apply the same discipline you would to application development: version control, code review, testing, and continuous improvement.
