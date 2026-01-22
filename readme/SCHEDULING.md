# GPU Instance Scheduling Documentation

## Overview

This infrastructure includes automated scheduling to start and stop GPU instances based on business hours across different time zones:

- **Start Time**: IST 9:30 AM (Indian Standard Time)
- **Stop Time**: Ethiopia Time 6:00 PM (East Africa Time)

## Time Zone Conversions

| Time Zone | Start | Stop |
|-----------|-------|------|
| **IST (UTC+5:30)** | 9:30 AM | 8:30 PM |
| **EAT (UTC+3)** | 7:00 AM | 6:00 PM |
| **UTC** | 4:00 AM | 3:00 PM |
| **EST (UTC-5)** | 11:00 PM (prev day) | 10:00 AM |
| **PST (UTC-8)** | 8:00 PM (prev day) | 7:00 AM |

## Schedule Implementation

### AWS

AWS uses Lambda functions triggered by EventBridge Scheduler:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   EventBridge   │────▶│     Lambda      │────▶│   EC2 / ASG     │
│   Scheduler     │     │   (Start/Stop)  │     │   Instances     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Cron Expressions:**
- Start: `cron(0 4 ? * MON-FRI *)` (04:00 UTC, Mon-Fri)
- Stop: `cron(0 15 ? * MON-FRI *)` (15:00 UTC, Mon-Fri)

**Lambda Functions:**
- `{name_prefix}-start-instances`: Resizes ASG to desired capacity
- `{name_prefix}-stop-instances`: Sets ASG capacity to 0

### Azure

Azure uses Automation Account with PowerShell runbooks:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Automation    │────▶│   PowerShell    │────▶│      VMSS       │
│   Schedule      │     │    Runbook      │     │   Instances     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Runbooks:**
- `{name_prefix}-start-vmss`: Starts VMSS instances and sets capacity
- `{name_prefix}-stop-vmss`: Stops and deallocates VMSS instances

### GCP

GCP uses Cloud Scheduler with Cloud Functions:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Cloud       │────▶│     Cloud       │────▶│      MIG        │
│   Scheduler     │     │   Functions     │     │   Instances     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Cloud Functions:**
- `{name_prefix}-start-instances`: Resizes MIG to target size
- `{name_prefix}-stop-instances`: Resizes MIG to 0

## Configuration Variables

```hcl
# Enable/disable scheduling
enable_scheduling = true

# Cron expressions (UTC)
schedule_start_cron = "cron(0 4 ? * MON-FRI *)"  # AWS format
schedule_stop_cron  = "cron(0 15 ? * MON-FRI *)" # AWS format
```

## Monitoring & Logging

### AWS
- CloudWatch Logs: `/aws/lambda/{name_prefix}-start-instances`
- CloudWatch Logs: `/aws/lambda/{name_prefix}-stop-instances`
- CloudWatch Alarms for Lambda errors

### Azure
- Log Analytics Workspace: `{name_prefix}-logs`
- Automation Account job logs
- Diagnostic settings for runbook execution

### GCP
- Cloud Logging: `resource.type="cloud_function"`
- Log-based metrics for function errors
- Cloud Monitoring alert policies

## Error Handling

All scheduler functions implement:

1. **Retry Logic**: 3 retries with exponential backoff
2. **Error Logging**: All errors logged to cloud-native logging service
3. **Alerting**: CloudWatch/Azure Monitor/Cloud Monitoring alerts on failures
4. **Idempotency**: Safe to run multiple times

## Manual Override

### AWS
```bash
# Manually start instances
aws lambda invoke \
  --function-name {name_prefix}-start-instances \
  --payload '{}' response.json

# Manually stop instances
aws lambda invoke \
  --function-name {name_prefix}-stop-instances \
  --payload '{}' response.json

# Update ASG directly
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name {asg_name} \
  --desired-capacity 1
```

### Azure
```bash
# Manually run start runbook
az automation runbook start \
  --resource-group {rg_name} \
  --automation-account-name {automation_name} \
  --name {name_prefix}-start-vmss

# Manually run stop runbook
az automation runbook start \
  --resource-group {rg_name} \
  --automation-account-name {automation_name} \
  --name {name_prefix}-stop-vmss
```

### GCP
```bash
# Manually trigger start function
gcloud functions call {name_prefix}-start-instances

# Manually trigger stop function
gcloud functions call {name_prefix}-stop-instances

# Update MIG directly
gcloud compute instance-groups managed resize {mig_name} \
  --region {region} \
  --size 1
```

## Cost Optimization

The scheduling feature is designed to minimize costs by:

1. Running instances only during business hours
2. Automatically stopping instances after business hours
3. Using ASG/VMSS/MIG capacity management instead of instance termination
4. Preserving instance configurations for fast startup

### Estimated Savings

Assuming 24/7 operation vs scheduled operation (Mon-Fri, 9:30 AM IST to 6:00 PM EAT):

| Instance Type | 24/7 Monthly | Scheduled Monthly | Savings |
|--------------|--------------|-------------------|---------|
| AWS g5.4xlarge | ~$2,500 | ~$750 | ~70% |
| Azure NV36ads_A10 | ~$3,000 | ~$900 | ~70% |
| GCP n1-standard-16+L4 | ~$2,200 | ~$660 | ~70% |

*Note: Actual costs vary by region and pricing changes*

## Customization

To adjust the schedule:

1. Modify `schedule_start_cron` and `schedule_stop_cron` in `terraform.tfvars`
2. Run `terraform apply`

### Weekend Operation

To include weekends:
```hcl
schedule_start_cron = "cron(0 4 ? * * *)"  # Every day
schedule_stop_cron  = "cron(0 15 ? * * *)" # Every day
```

### Different Hours

To adjust to different business hours (e.g., 8 AM - 8 PM UTC):
```hcl
schedule_start_cron = "cron(0 8 ? * MON-FRI *)"
schedule_stop_cron  = "cron(0 20 ? * MON-FRI *)"
```

## Troubleshooting

### Instances Not Starting

1. Check scheduler logs for errors
2. Verify IAM permissions
3. Check if ASG/VMSS/MIG has capacity available
4. Verify instance type availability in region

### Instances Not Stopping

1. Check scheduler logs for errors
2. Verify IAM permissions
3. Check for running processes preventing shutdown
4. Manual override may be needed

### Lambda/Function Errors

1. Check CloudWatch/Cloud Logging
2. Verify environment variables
3. Check IAM role permissions
4. Verify VPC connectivity (if applicable)
