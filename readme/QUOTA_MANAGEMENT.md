# AWS Intelligent Quota-Based Deployment

## Overview

The deployment script now includes an **intelligent quota checker** that automatically detects your AWS account's GPU instance quotas and selects the best pricing model (On-Demand or Spot) based on availability.

## How It Works

### Automatic Quota Detection

When you run the deployment, the system will:

1. **Check your requested instance type** (e.g., `g5.4xlarge`)
2. **Query AWS Service Quotas API** for:
   - On-Demand G and VT instances quota (`L-DB2E81BA`)
   - Spot G and VT instances quota (`L-3819A6DF`)
3. **Calculate vCPU requirements** for your instance type
4. **Compare available quotas** against requirements
5. **Automatically select** the best pricing model

### Decision Logic

The system follows this priority:

1. ✅ **Spot Instances** (preferred for cost savings - up to 90% off)
   - If Spot quota ≥ required vCPUs → Use Spot
   
2. ✅ **On-Demand Instances** (fallback for guaranteed availability)
   - If Spot insufficient but On-Demand quota ≥ required vCPUs → Use On-Demand
   
3. ⚠️ **Alternative Instance Types** (if both quotas insufficient)
   - Automatically finds smaller GPU instances that fit within quota
   - Presents available options: `g4dn.xlarge`, `g4dn.2xlarge`, `g5.xlarge`, `g5.2xlarge`
   
4. ❌ **Request Quota Increase** (if no alternatives available)
   - Displays instructions for requesting quota increase
   - Provides AWS CLI commands and console links

## Example Scenarios

### Scenario 1: Spot Quota Available ✓

```
Current Account Quotas:
- On-Demand G Instances: 0 vCPUs
- Spot G Instances: 64 vCPUs

Requested: g5.4xlarge (16 vCPUs)

✓ Result: Automatically uses Spot instances
```

### Scenario 2: Only On-Demand Available ✓

```
Current Account Quotas:
- On-Demand G Instances: 64 vCPUs
- Spot G Instances: 0 vCPUs

Requested: g5.4xlarge (16 vCPUs)

✓ Result: Automatically uses On-Demand instances
```

### Scenario 3: Insufficient Quota for Requested Type ⚠️

```
Current Account Quotas:
- On-Demand G Instances: 0 vCPUs
- Spot G Instances: 4 vCPUs

Requested: g5.4xlarge (16 vCPUs - TOO LARGE)

⚠️ Result: Offers alternatives that fit in 4 vCPU quota
Options:
  ✓ g4dn.xlarge (4 vCPUs) - Spot
  ✓ g5.xlarge (4 vCPUs) - Spot
```

### Scenario 4: No Quota Available ❌

```
Current Account Quotas:
- On-Demand G Instances: 0 vCPUs
- Spot G Instances: 0 vCPUs

Requested: g5.4xlarge (16 vCPUs)

❌ Result: Deployment blocked
Action: Must request quota increase from AWS
```

## Quota Increase Instructions

### Option 1: AWS Console (Recommended)

1. Go to [AWS Service Quotas Console](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas)
2. Search for:
   - **On-Demand**: "Running On-Demand G and VT instances" (L-DB2E81BA)
   - **Spot**: "All G and VT Spot Instance Requests" (L-3819A6DF)
3. Click "Request increase at account-level"
4. Enter desired value: **64 vCPUs** (allows up to 4x g5.4xlarge instances)
5. Provide justification: "GPU instances for machine learning workloads"
6. Submit request

**Processing Time:** Typically 24-48 hours

### Option 2: AWS CLI

#### For Spot Instances (Recommended):
```bash
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-3819A6DF \
  --desired-value 64 \
  --region us-east-1
```

#### For On-Demand Instances:
```bash
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-DB2E81BA \
  --desired-value 64 \
  --region us-east-1
```

## vCPU Requirements by Instance Type

| Instance Type | vCPUs | GPU | Memory | Use Case |
|---------------|-------|-----|---------|----------|
| `g4dn.xlarge` | 4 | 1x T4 (16GB) | 16 GB | Small models, testing |
| `g4dn.2xlarge` | 8 | 1x T4 (16GB) | 32 GB | Medium models |
| `g5.xlarge` | 4 | 1x A10G (24GB) | 16 GB | Modern GPUs, small-medium models |
| `g5.2xlarge` | 8 | 1x A10G (24GB) | 32 GB | Medium-large models |
| `g5.4xlarge` | 16 | 1x A10G (24GB) | 64 GB | Large models, production |
| `g5.8xlarge` | 32 | 1x A10G (24GB) | 128 GB | Very large models |

## Configuration File

The deployment automatically updates your `terraform.tfvars` with:

```hcl
# Automatically set based on quota detection
use_spot_instances = true  # or false

# You can override if needed
instance_type = "g5.4xlarge"
```

## Manual Override

If you want to override the automatic selection:

### Edit terraform.tfvars:
```hcl
use_spot_instances = false  # Force On-Demand
instance_type = "g4dn.xlarge"  # Use different instance
```

### Re-run deployment:
```bash
./deploy.sh --auto
```

## Deployment Flow

```
Start Deployment
    ↓
Check Prerequisites (Terraform, AWS CLI, jq)
    ↓
Validate AWS Credentials
    ↓
Check IAM Permissions (200+ permissions)
    ↓
Select Region & Instance Type
    ↓
┌─────────────────────────────────────────┐
│  INTELLIGENT QUOTA CHECKER (NEW!)       │
│  • Query On-Demand G quota              │
│  • Query Spot G quota                   │
│  • Calculate vCPU requirements          │
│  • Auto-select best pricing model       │
│  • Or suggest alternatives              │
└─────────────────────────────────────────┘
    ↓
Generate Terraform Config
    ↓
Terraform Init → Validate → Plan → Apply
    ↓
Deploy Infrastructure
    ↓
✓ Complete
```

## Troubleshooting

### Error: "Insufficient quota for g5.4xlarge"

**Solution:** Choose one of the alternatives or request quota increase

### Error: "No quota available"

**Solution:** Must request quota increase (24-48 hour wait)

### Quota increase request denied

**Solution:** 
- Provide more detailed justification
- Start with smaller quota (e.g., 16 vCPUs for 1 instance)
- Build usage history with smaller instances first

### Spot instances terminated during workload

**Solution:** 
- Request On-Demand quota increase
- Use Spot for dev/test, On-Demand for production
- Implement checkpointing in your application

## Best Practices

1. **Start Small**: Request 16-32 vCPUs initially, increase as needed
2. **Use Spot for Dev/Test**: Save 70-90% on costs
3. **Reserve On-Demand for Production**: Guaranteed availability
4. **Monitor Spot Interruptions**: Set up CloudWatch alarms
5. **Auto-scaling**: Configure ASG to handle spot interruptions
6. **Checkpointing**: Save model state regularly

## Cost Comparison

| Instance Type | On-Demand Price | Spot Price (avg) | Savings |
|---------------|-----------------|------------------|---------|
| `g4dn.xlarge` | $0.526/hr | $0.158/hr | 70% |
| `g4dn.2xlarge` | $0.752/hr | $0.226/hr | 70% |
| `g5.xlarge` | $1.006/hr | $0.302/hr | 70% |
| `g5.2xlarge` | $1.212/hr | $0.364/hr | 70% |
| `g5.4xlarge` | $1.624/hr | $0.487/hr | 70% |

*Prices for us-east-1 region (January 2026)*

## Support

For issues or questions:
- Check AWS Service Quotas dashboard
- Review CloudWatch logs for Terraform errors
- Contact AWS Support for quota increase status
- Check this documentation: `/readme/QUOTA_MANAGEMENT.md`
