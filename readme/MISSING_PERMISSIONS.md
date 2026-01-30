# AWS IAM Permissions for DPG GPU Infrastructure Deployment

## Overview

The DPG deployment script automatically checks for required AWS IAM permissions before executing Terraform. This ensures that deployment failures due to missing permissions are caught early, saving time and preventing partial infrastructure states.

## Pre-Deployment Permission Check

When you run `./deploy.sh`, the script will:

1. **Validate your AWS credentials** - Ensures your access keys are valid
2. **Check all required permissions** - Uses `iam:SimulatePrincipalPolicy` to verify you have the necessary permissions
3. **Report missing permissions** - Displays a clear list of what's missing
4. **Provide next steps** - Guides you on how to obtain the required permissions

---

## Required AWS Permissions

### Complete Policy File

The complete IAM policy required for deployment is located at:
```
aws-terraform-user-policy.json
```

### Permission Categories

#### EC2 (Compute & Networking)
- Full EC2 access for VPC, subnets, security groups, instances, NAT gateways, etc.

#### IAM (Identity & Access Management)
- Create/manage roles for EC2 instances, Lambda functions, and VPC Flow Logs
- Create/manage instance profiles
- Attach/detach policies
- Pass roles to services (EC2, Lambda)

#### Lambda (Serverless Functions)
- Create/manage Lambda functions for instance scheduling

#### EventBridge (Scheduling)
- Create rules and targets for start/stop schedules

#### CloudWatch (Monitoring & Logging)
- Create log groups, log streams
- Put metrics and alarms

#### Elastic Load Balancing
- Create/manage Application Load Balancers and target groups

#### Auto Scaling
- Create/manage Auto Scaling groups

---

## If Permissions Are Missing

### What You'll See

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠  MISSING AWS PERMISSIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Your AWS account is missing the following permissions required
  to deploy the DPG infrastructure:

  iam:
    ✗ iam:CreateInstanceProfile
    ✗ iam:DeleteInstanceProfile

  ec2:
    ✗ ec2:CreateVpc
    ...
```

### What To Do

#### Option 1: Request Permissions from Your AWS Administrator

1. Locate the policy file: `aws-terraform-user-policy.json`
2. Send this file to your AWS Administrator
3. Ask them to create an IAM policy with this content
4. Have them attach the policy to your IAM user or role

**Email Template for Your Admin:**
```
Subject: Request for IAM Permissions - DPG Infrastructure Deployment

Hi,

I need to deploy the Digital Public Goods (DPG) GPU infrastructure on AWS.
The deployment requires specific IAM permissions that I currently don't have.

Please find attached the required IAM policy document (aws-terraform-user-policy.json).

Could you please:
1. Create a new IAM policy with the attached JSON content
2. Attach this policy to my IAM user: [YOUR_USERNAME]

The permissions are scoped to resources prefixed with "dpg-infra-*" where possible
to follow the principle of least privilege.

Thank you!
```

#### Option 2: Use Administrator Credentials

If you have access to an AWS account with Administrator access, you can use those credentials instead.

---

## Administrator Guide

### Creating the IAM Policy

1. Log into the AWS Console
2. Navigate to **IAM → Policies → Create policy**
3. Click **JSON** tab
4. Paste the contents of `aws-terraform-user-policy.json`
5. Click **Next**
6. Name the policy: `DPG-Infrastructure-Deployment-Policy`
7. Add description: `Permissions required for deploying DPG GPU infrastructure via Terraform`
8. Click **Create policy**

### Attaching the Policy to a User

1. Navigate to **IAM → Users**
2. Select the user who needs deployment access
3. Click **Add permissions → Attach policies directly**
4. Search for `DPG-Infrastructure-Deployment-Policy`
5. Check the box and click **Add permissions**

### Security Considerations

The policy follows AWS best practices:

- **Resource Scoping**: IAM permissions are scoped to `dpg-infra-*` prefixed resources
- **Service Boundaries**: Only includes services required for the infrastructure
- **Condition Keys**: PassRole is restricted to specific services (EC2, Lambda)

---

## Troubleshooting

### "Cannot simulate IAM policies"

If you see this warning, your account lacks the `iam:SimulatePrincipalPolicy` permission. The script will fall back to basic service access checks.

### "Permission check passed but Terraform still fails"

The permission checker simulates policy evaluation but cannot account for:
- Service Control Policies (SCPs) at the AWS Organization level
- Permission boundaries on your IAM user/role
- Resource-based policies that may deny access

Contact your AWS Administrator if you encounter access denied errors despite passing the permission check.

### Generating a Permission Report

When permissions are missing, the script automatically generates:
- `missing-permissions-report.txt` - A detailed report you can share with your admin

---

## Historical Issues

### iam:CreateInstanceProfile (Resolved)

**Status:** Previously BLOCKING - Now included in permission checks

**Error:**
```
Error: creating IAM Instance Profile (dpg-infra-staging-instance-profile): 
operation error IAM: CreateInstanceProfile, api error AccessDenied
```

**Solution:** Ensure your policy includes:
```json
{
  "Effect": "Allow",
  "Action": [
    "iam:CreateInstanceProfile",
    "iam:DeleteInstanceProfile"
  ],
  "Resource": "arn:aws:iam::*:instance-profile/dpg-infra-*"
}
```
- `iam:DeleteInstanceProfile` - Needed for `terraform destroy` to clean up the instance profile

### For User (Satya):
Once the permission is granted, run:
```bash
AWS_PROFILE=satya terraform apply -auto-approve
```

The deployment will continue from where it failed and complete the following:
- Create the IAM Instance Profile
- Create EC2 Launch Template
- Create Auto Scaling Group with GPU instances
- Complete load balancer configuration
- Deploy Lambda functions

---

## Testing Summary

**Test Date:** January 29, 2026

**Test Steps:**
1. ✅ Ran `terraform plan` - No errors
2. ✅ Ran `terraform init` - Successful
3. ✅ Started `terraform apply` - Created 30+ resources successfully
4. ❌ Hit `iam:CreateInstanceProfile` permission error at resource #31

**Current State:**
- Terraform state contains partially applied resources
- All network and IAM infrastructure is in place
- Ready to resume once permission is granted
- No orphaned resources (all created resources are tracked in state)

---

## Related AWS IAM Actions (for reference)

The following related permissions are already working:
- `iam:ListRoles` - ✅ Works
- `iam:GetRole` - ✅ Works
- `iam:ListRolePolicies` - ✅ Works (no longer missing)
- `iam:GetRolePolicy` - ✅ Works
- `iam:CreateRole` - ✅ Works
- `iam:DeleteRole` - ✅ Works
- `iam:AttachRolePolicy` - ✅ Works
- `iam:DetachRolePolicy` - ✅ Works
- `iam:PutRolePolicy` - ✅ Works
- `iam:ListAttachedRolePolicies` - ✅ Works (no longer missing)

---

## Impact

**Without this permission:**
- Cannot create EC2 instances (blocked at terraform apply)
- Cannot scale infrastructure up/down
- Cannot redeploy after destroy (blocked on reapply)

**With this permission:**
- Full infrastructure deployment automation
- Seamless scaling and redeployment
- Complete infrastructure lifecycle management (create, update, destroy)

