# DPG GPU Infrastructure - Multi-Cloud Terraform Deployment

A comprehensive Terraform boilerplate for deploying GPU instances across AWS, Azure, and GCP with automatic NVIDIA driver installation, load balancing, auto-scaling, and scheduled start/stop automation.

## ✨ Key Features

- **Multi-Cloud Support**: AWS, Azure, GCP with directory-based isolation
- **Single Provider Authentication**: Only authenticate with your chosen provider
- **GPU Detection**: Automatic detection of NVIDIA hardware and drivers
- **Automatic Driver Installation**: NVIDIA Driver v550 + CUDA 12.4
- **Load Balancing**: ALB (AWS), Azure LB, Global HTTPS LB (GCP)
- **Auto-Scaling**: Instance groups with health monitoring
- **Scheduled Operations**: IST 9:30 AM to Ethiopia Time 6:00 PM
- **Security**: Least privilege IAM policies, VPC isolation
- **Modular Deploy Scripts**: Feature-based script organization
- **Modular Code Structure**: Large files split into smaller, focused modules

## 🏗️ Architecture

The project follows **directory-based isolation** per cloud provider with **modular code organization**:

```
DPG-terraform-gpu-infra/
├── deploy.sh                  # Main entry point (sources modular scripts)
├── deploy/                    # Modular deployment scripts
│   ├── config.sh              # Configuration, constants, color definitions
│   ├── utils.sh               # Loader for utility modules
│   │   ├── utils_logging.sh   # log() function with color-coded levels
│   │   ├── utils_ui.sh        # print_banner(), print_help(), spinner(), confirm()
│   │   ├── utils_progress.sh  # Progress bar and terraform progress tracking
│   │   └── utils_state.sh     # State management (save/get/show)
│   ├── prerequisites.sh       # System checks, CLI validation
│   ├── prompts.sh             # Interactive platform/region/template selection
│   ├── credentials.sh         # AWS/Azure/GCP/OnPrem credential configuration
│   └── terraform.sh           # Loader for terraform modules
│       ├── terraform_init.sh      # terraform init/validate
│       ├── terraform_plan.sh      # terraform plan, resource checks
│       ├── terraform_apply.sh     # terraform apply, show outputs
│       ├── terraform_destroy.sh   # terraform destroy
│       └── terraform_config.sh    # Configuration generation
├── variables.tf               # Consolidated variables (references variables/ folder)
├── variables/                 # Modular variable definitions (8 files - reference only)
│   ├── variables_common.tf    # General config, cloud provider, tags
│   ├── variables_aws.tf       # AWS credentials, region mappings, instances
│   ├── variables_azure.tf     # Azure credentials, region mappings
│   ├── variables_gcp.tf       # GCP credentials, region mappings
│   ├── variables_compute.tf   # Volume, auto-scaling, NVIDIA config
│   ├── variables_network.tf   # VPC, subnets, SSH key config
│   ├── variables_scheduling.tf # Start/stop scheduling config
│   └── variables_loadbalancer.tf # LB and health check config
├── environments/              # ← Deploy from here (per-provider isolation)
│   ├── aws/
│   │   ├── dev/               # AWS development environment
│   │   ├── staging/           # AWS staging environment
│   │   └── prod/              # AWS production environment
│   ├── azure/
│   │   ├── dev/               # Azure development environment
│   │   ├── staging/           # Azure staging environment
│   │   └── prod/              # Azure production environment
│   └── gcp/
│       ├── dev/               # GCP development environment
│       ├── staging/           # GCP staging environment
│       └── prod/              # GCP production environment
├── modules/                   # Reusable infrastructure modules
│   ├── aws/                   # AWS resources (EC2, VPC, ALB, Lambda)
│   │   ├── compute.tf         # EC2 instances, ASG, AMI lookup
│   │   ├── vpc.tf             # VPC and Internet Gateway
│   │   ├── subnets.tf         # Public and private subnets
│   │   ├── nat.tf             # Elastic IPs and NAT Gateways
│   │   ├── routing.tf         # Route tables and associations
│   │   ├── security_groups.tf # ALB and instance security groups
│   │   ├── flow_logs.tf       # VPC Flow Logs with IAM role
│   │   ├── loadbalancer.tf    # ALB, target groups, listeners
│   │   ├── scheduler.tf       # Lambda functions for start/stop
│   │   ├── iam.tf             # IAM roles and policies
│   │   └── templates/         # User data, Lambda function templates
│   ├── azure/                 # Azure resources (VMSS, VNet, LB)
│   │   ├── compute.tf         # VM Scale Sets, images
│   │   ├── networking.tf      # VNet, subnets, NSGs
│   │   ├── loadbalancer.tf    # Azure Load Balancer
│   │   ├── scheduler.tf       # Automation runbooks
│   │   └── templates/         # Cloud-init templates
│   ├── gcp/                   # GCP resources (MIG, VPC, LB)
│   │   ├── compute.tf         # Managed Instance Groups
│   │   ├── networking.tf      # VPC, subnets, firewall rules
│   │   ├── loadbalancer.tf    # HTTPS Load Balancer
│   │   ├── scheduler_iam.tf       # Service account, IAM roles
│   │   ├── scheduler_functions.tf # Cloud Storage, function archives
│   │   ├── scheduler_jobs.tf      # Cloud Scheduler jobs
│   │   ├── scheduler_monitoring.tf # Log-based metrics, alerts
│   │   └── templates/         # Startup scripts, Cloud Functions
│   └── shared/                # Common variables and locals
│       ├── variables.tf       # Shared variable definitions
│       ├── locals.tf          # Common computed values
│       └── outputs.tf         # Shared outputs
├── scripts/                   # Helper scripts (modular)
│   ├── init.sh                # Project initialization (loader)
│   │   ├── init_checks.sh     # Prerequisites and GPU detection
│   │   ├── init_providers.sh  # Cloud provider credential collection
│   │   └── init_terraform.sh  # tfvars generation, terraform init
│   ├── detect_gpu.sh          # GPU hardware detection
│   └── validate.sh            # Configuration validation
├── docs/                      # Additional documentation
└── readme/                    # README component files
    └── SCHEDULING.md          # Scheduling documentation
```

## 📊 Functional Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DPG DEPLOYMENT FLOW                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   START     │───▶│  deploy.sh  │───▶│   Source    │───▶│ Prerequisites│
│             │    │  (Entry)    │    │   Modules   │    │    Check    │
└─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘
                                                                 │
                   ┌────────────────────────────────────────────▼───────────┐
                   │                    INTERACTIVE MODE                     │
                   └────────────────────────────────────────────────────────┘
                                           │
        ┌──────────────────────────────────┼──────────────────────────────────┐
        ▼                                  ▼                                  ▼
┌──────────────┐                  ┌──────────────┐                  ┌──────────────┐
│   Platform   │                  │    Region    │                  │   Template   │
│  Selection   │                  │  Selection   │                  │  Selection   │
│  (prompts.sh)│                  │  (prompts.sh)│                  │  (prompts.sh)│
└──────┬───────┘                  └──────┬───────┘                  └──────┬───────┘
       │                                 │                                 │
       │  ┌───────────────────┬──────────┴───────────┬───────────────────┐│
       ▼  ▼                   ▼                      ▼                   ▼▼
┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│     AWS     │       │    Azure    │       │     GCP     │       │   On-Prem   │
│ credentials │       │ credentials │       │ credentials │       │ credentials │
│  (creds.sh) │       │  (creds.sh) │       │  (creds.sh) │       │  (creds.sh) │
└──────┬──────┘       └──────┬──────┘       └──────┬──────┘       └──────┬──────┘
       │                     │                     │                     │
       └──────────────────────┬─────────────────────┘                    │
                              ▼                                          ▼
                   ┌─────────────────────┐                    ┌─────────────────┐
                   │  Set Working Dir    │                    │  Local Ansible  │
                   │ environments/{platform}                  │   Provisioning  │
                   │   /{environment}/   │                    │                 │
                   └──────────┬──────────┘                    └─────────────────┘
                              │
                              ▼
              ┌──────────────────────────────┐
              │     TERRAFORM OPERATIONS     │
              │       (terraform.sh)         │
              └──────────────────────────────┘
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│   terraform │       │   terraform │       │   terraform │
│     init    │──────▶│   validate  │──────▶│     plan    │
└─────────────┘       └─────────────┘       └──────┬──────┘
                                                    │
                                                    ▼
                                           ┌─────────────┐
                                           │   terraform │
                                           │    apply    │
                                           └──────┬──────┘
                                                   │
                                                   ▼
                                          ┌──────────────┐
                                          │    Show      │
                                          │   Outputs    │
                                          │   & Status   │
                                          └──────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEPLOY SCRIPT MODULES                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   config.sh     │  │    utils.sh     │  │prerequisites.sh │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ • VERSION       │  │ Loads:          │  │ • check_prereq  │
│ • Colors        │  │ • utils_logging │  │ • check_cli     │
│ • Directories   │  │ • utils_ui      │  │ • validate_creds│
│ • GPU models    │  │ • utils_progress│  │                 │
│ • Regions       │  │ • utils_state   │  │                 │
│ • Instances     │  │                 │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   prompts.sh    │  │  credentials.sh │  │  terraform.sh   │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ • select_       │  │ • configure_aws │  │ Loads:          │
│   platform      │  │ • configure_    │  │ • terraform_init│
│ • select_region │  │   azure         │  │ • terraform_plan│
│ • select_       │  │ • configure_gcp │  │ • terraform_    │
│   template      │  │ • configure_    │  │   apply         │
│ • show_gpu_     │  │   onprem        │  │ • terraform_    │
│   options       │  │                 │  │   destroy       │
│                 │  │                 │  │ • terraform_cfg │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         VARIABLES ORGANIZATION                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐
│variables_common │  │ variables_aws   │  │variables_azure  │  │variables_gcp │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤  ├──────────────┤
│ • cloud_provider│  │ • aws_region    │  │ • azure_location│  │ • gcp_project│
│ • project_name  │  │ • aws_access_key│  │ • azure_sub_id  │  │ • gcp_region │
│ • environment   │  │ • aws_instances │  │ • azure_client  │  │ • gcp_zone   │
│ • owner/tags    │  │ • aws_az_map    │  │ • azure_tenant  │  │ • gcp_creds  │
└─────────────────┘  └─────────────────┘  └─────────────────┘  └──────────────┘

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐
│variables_compute│  │variables_network│  │variables_sched  │  │variables_lb  │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤  ├──────────────┤
│ • root_volume   │  │ • vpc_cidr      │  │ • enable_sched  │  │ • enable_lb  │
│ • auto_scaling  │  │ • subnet_cidrs  │  │ • start_time    │  │ • lb_type    │
│ • nvidia_driver │  │ • ssh_key       │  │ • stop_time     │  │ • health_chk │
│ • cuda_version  │  │ • public_access │  │ • timezone      │  │ • ssl_cert   │
└─────────────────┘  └─────────────────┘  └─────────────────┘  └──────────────┘
```

## 🚀 Quick Start

### Option 1: Interactive Wizard (Recommended)

```bash
./deploy.sh
```

### Option 2: Direct Terraform Commands

```bash
cd environments/aws/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### Option 3: Automated Deployment

```bash
./deploy.sh --platform aws --environment staging --auto
```

## 💻 GPU Instances

| Cloud | Instance Type | GPU | Memory |
|-------|---------------|-----|--------|
| AWS | g4dn.xlarge | NVIDIA T4 16GB | 16GB RAM |
| AWS | g5.xlarge | NVIDIA A10G 24GB | 16GB RAM |
| Azure | Standard_NC4as_T4_v3 | NVIDIA T4 16GB | 28GB RAM |
| GCP | n1-standard-4 + T4 | NVIDIA T4 16GB | 15GB RAM |

## 📁 Environment Configuration

Each environment contains:

| File | Purpose |
|------|---------|
| `main.tf` | Provider config + module calls |
| `variables.tf` | Variable definitions |
| `terraform.tfvars.example` | Template (copy to terraform.tfvars) |
| `outputs.tf` | Output definitions |

### AWS Setup

```bash
cd environments/aws/staging
cp terraform.tfvars.example terraform.tfvars

# Configure credentials
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

terraform init && terraform apply
```

### Azure Setup

```bash
cd environments/azure/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set azure_subscription_id

az login
terraform init && terraform apply
```

### GCP Setup

```bash
cd environments/gcp/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set gcp_project_id

gcloud auth application-default login
terraform init && terraform apply
```

## 🕐 Scheduling

Instances run from **IST 9:30 AM** to **Ethiopia Time 6:00 PM**:

| Action | UTC | IST | EAT |
|--------|-----|-----|-----|
| Start | 04:00 | 09:30 | 07:00 |
| Stop | 15:00 | 20:30 | 18:00 |

## 📋 Command Reference

```bash
./deploy.sh                                    # Interactive wizard
./deploy.sh -p aws -e staging --plan           # Plan only
./deploy.sh -p aws -e staging --validate       # Validate config
./deploy.sh -p aws -e staging --destroy        # Destroy infra
./deploy.sh --help                             # Show help
```

## 🔧 Prerequisites

1. Terraform >= 1.5.0
2. Cloud CLI tools (aws-cli, az-cli, gcloud)
3. Valid cloud credentials for your chosen provider

## � Modular Code Structure

The codebase has been refactored for better maintainability:

### Variables Organization (`variables.tf` + `variables/` folder)

The root `variables.tf` contains all variable definitions consolidated from the modular files in `variables/` folder:

| Section | Source File | Purpose |
|---------|-------------|---------|
| Section 1 | `variables_common.tf` | Cloud provider, project name, environment, tags |
| Section 2 | `variables_aws.tf` | AWS credentials, regions, instance types |
| Section 3 | `variables_azure.tf` | Azure credentials, locations, VM sizes |
| Section 4 | `variables_gcp.tf` | GCP project, regions, machine types |
| Section 5 | `variables_compute.tf` | Volume, auto-scaling, NVIDIA config |
| Section 6 | `variables_network.tf` | VPC, subnets, SSH key settings |
| Section 7 | `variables_scheduling.tf` | Start/stop times, timezone |
| Section 8 | `variables_loadbalancer.tf` | LB type, health checks, SSL |

The `variables/` folder is kept for organizational reference and documentation.

### Deploy Scripts (`deploy/` folder)
| Module | Sub-modules | Purpose |
|--------|-------------|---------|
| `utils.sh` | `utils_logging.sh`, `utils_ui.sh`, `utils_progress.sh`, `utils_state.sh` | Logging, UI, progress tracking, state management |
| `terraform.sh` | `terraform_init.sh`, `terraform_plan.sh`, `terraform_apply.sh`, `terraform_destroy.sh`, `terraform_config.sh` | Terraform operations |

### AWS Networking (`modules/aws/`)
| File | Purpose |
|------|---------|
| `vpc.tf` | VPC and Internet Gateway |
| `subnets.tf` | Public and private subnets |
| `nat.tf` | Elastic IPs and NAT Gateways |
| `routing.tf` | Route tables and associations |
| `security_groups.tf` | ALB and instance security groups |
| `flow_logs.tf` | VPC Flow Logs with IAM role |

### GCP Scheduler (`modules/gcp/`)
| File | Purpose |
|------|---------|
| `scheduler_iam.tf` | Service account, IAM roles |
| `scheduler_functions.tf` | Cloud Storage, function archives |
| `scheduler_jobs.tf` | Cloud Scheduler jobs |
| `scheduler_monitoring.tf` | Log-based metrics, alerts |

### Init Scripts (`scripts/`)
| File | Purpose |
|------|---------|
| `init.sh` | Main loader script |
| `init_checks.sh` | Prerequisites and GPU detection |
| `init_providers.sh` | Cloud provider credential collection |
| `init_terraform.sh` | tfvars generation, terraform init |

## �📄 License

MIT License - OpenAgriNet (The Next GEN Agri Tech)
