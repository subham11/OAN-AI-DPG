# Multi-Cloud GPU Infrastructure Terraform

A comprehensive Terraform boilerplate for deploying GPU instances across AWS, Azure, and GCP with automatic NVIDIA driver installation, load balancing, auto-scaling, and scheduled start/stop automation.

## Features

- **Multi-Cloud Support**: AWS, Azure, GCP
- **GPU Detection**: Automatic detection of NVIDIA hardware and drivers
- **Automatic Driver Installation**: NVIDIA Driver v550 + CUDA 12.4
- **Load Balancing**: ALB (AWS), Azure LB, Global HTTPS LB (GCP)
- **Auto-Scaling**: Instance groups with health monitoring
- **Scheduled Operations**: IST 9:30 AM to Ethiopia Time 6:00 PM
- **Security**: Least privilege IAM policies, VPC isolation

## GPU Instances

| Cloud | Instance Type | GPU |
|-------|--------------|-----|
| AWS | g5.4xlarge | NVIDIA A10G |
| Azure | Standard_NV36ads_A10_v5 | NVIDIA A10 |
| GCP | n1-standard-16 + L4 | NVIDIA L4 |

## Directory Structure

```
terraform-gpu-infra/
├── main.tf                    # Root module entry point
├── variables.tf               # Root variables
├── outputs.tf                 # Root outputs
├── providers.tf               # Provider configurations
├── versions.tf                # Version constraints
├── terraform.tfvars.example   # Example variables file
├── modules/
│   ├── aws/                   # AWS-specific resources
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── compute.tf         # EC2, ASG
│   │   ├── networking.tf      # VPC, Subnets, SG
│   │   ├── loadbalancer.tf    # ALB
│   │   ├── scheduler.tf       # Lambda + EventBridge
│   │   └── iam.tf             # IAM roles/policies
│   ├── azure/                 # Azure-specific resources
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── compute.tf         # VMSS
│   │   ├── networking.tf      # VNet, NSG
│   │   ├── loadbalancer.tf    # Azure LB
│   │   └── scheduler.tf       # Automation Account
│   ├── gcp/                   # GCP-specific resources
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── compute.tf         # MIG
│   │   ├── networking.tf      # VPC, Firewall
│   │   ├── loadbalancer.tf    # Global HTTPS LB
│   │   └── scheduler.tf       # Cloud Scheduler
│   └── common/                # Shared utilities
│       ├── gpu_detection.sh   # GPU detection script
│       └── nvidia_install.sh  # NVIDIA driver installer
├── scripts/
│   ├── detect_gpu.sh          # Local GPU detection
│   ├── init.sh                # Interactive setup
│   └── validate.sh            # Post-deployment validation
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── docs/
    └── SCHEDULING.md          # Scheduling documentation
```

## Prerequisites

1. Terraform >= 1.5.0
2. Cloud CLI tools (aws-cli, az-cli, gcloud)
3. Valid cloud credentials

## Quick Start

### 1. Local GPU Detection

```bash
./scripts/detect_gpu.sh
```

### 2. Interactive Setup

```bash
./scripts/init.sh
```

### 3. Manual Deployment

```bash
# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

## Scheduling

Instances run from **IST 9:30 AM** to **Ethiopia Time 6:00 PM**:

- **Start**: 04:00 UTC (9:30 AM IST)
- **Stop**: 15:00 UTC (6:00 PM EAT)

## Environment Variables

### AWS
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-south-1"
```

### Azure
```bash
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

### GCP
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
export GOOGLE_PROJECT="your-project-id"
```

## License

MIT License - OpenAgriNet (The Next GEN Agri Tech)
