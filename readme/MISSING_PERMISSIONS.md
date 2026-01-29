# Missing IAM Permissions for DPG GPU Infrastructure Deployment

## Summary
After running `terraform apply`, **1 critical IAM permission** was identified as missing that blocks the complete infrastructure deployment.

---

## Missing Permission Details

### 1. **iam:CreateInstanceProfile** ⚠️ CRITICAL

**Status:** BLOCKING - Prevents EC2 instance creation

**Error Message:**
```
Error: creating IAM Instance Profile (dpg-infra-staging-instance-profile): 
operation error IAM: CreateInstanceProfile, https response error StatusCode: 403, 
RequestID: 8f04a2ea-d0f2-4a6e-a063-9438b5472052, api error AccessDenied: 

User: arn:aws:iam::379220350808:user/Satya is not authorized to perform: 
iam:CreateInstanceProfile on resource: 
arn:aws:iam::379220350808:instance-profile/dpg-infra-staging-instance-profile 
because no identity-based policy allows the iam:CreateInstanceProfile action
```

**Location in Code:**
- File: `modules/aws/compute.tf`
- Line: 37
- Resource: `aws_iam_instance_profile.instance`

**What It Does:**
Creates an IAM Instance Profile that links an EC2 instance role to EC2 instances. This allows EC2 instances to assume the role and access AWS services (like S3, CloudWatch, Systems Manager) with the permissions granted to that role.

**Required for Terraform Operations:**
- `terraform apply` - Creates EC2 instances that need the instance profile
- `terraform destroy` - Deletes the instance profile when tearing down infrastructure

**Related Permissions Working:**
- ✅ `iam:CreateRole` - Successfully created instance role
- ✅ `iam:CreatePolicy` - Successfully created policies
- ✅ `iam:AttachRolePolicy` - Successfully attached policies to roles
- ✅ `iam:PutRolePolicy` - Successfully added inline policies to roles
- ✅ `iam:DeleteRole` - Would work for cleanup
- ✅ `iam:DeletePolicy` - Would work for cleanup

---

## What Was Successfully Created

Before hitting the permission error, Terraform successfully created:

### Network Infrastructure ✅
- VPC with CIDR 10.0.0.0/16
- 2 Public Subnets
- 2 Private Subnets
- Internet Gateway
- 2 NAT Gateways
- 2 Elastic IPs
- Route tables (public and private)
- Route table associations

### IAM Resources ✅
- `dpg-infra-staging-instance-role` (EC2 instance role)
- `dpg-infra-staging-scheduler-lambda-role` (Lambda execution role)
- `dpg-infra-staging-vpc-flow-logs-role` (VPC Flow Logs role)
- Policy attachments (SSM, CloudWatch, Lambda basic execution)
- Custom policies for logging and scheduling

### EventBridge & Monitoring ✅
- CloudWatch Event Rules (start/stop instances on schedule)
- CloudWatch Log Groups for Lambda functions
- VPC Flow Logs configuration

### Load Balancer ✅
- Application Load Balancer target group

### Security Groups ✅
- ALB security group
- Instance security group

---

## Action Required

### For Administrator:
Add the following IAM permission to the Satya user's inline policy:

```json
{
  "Effect": "Allow",
  "Action": [
    "iam:CreateInstanceProfile",
    "iam:DeleteInstanceProfile"
  ],
  "Resource": "arn:aws:iam::379220350808:instance-profile/*"
}
```

**Rationale:**
- `iam:CreateInstanceProfile` - Needed for `terraform apply` to create the instance profile
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

