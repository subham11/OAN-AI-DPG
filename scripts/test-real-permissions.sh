#!/bin/bash

echo "======================================"
echo "Practical Permission Testing"
echo "======================================"

# Test 1: EC2 Permissions
echo -e "\n1. Testing EC2:RunInstances (dry-run)..."
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type g5.4xlarge \
  --dry-run 2>&1 | grep -q "DryRunOperation" && \
  echo "✅ ec2:RunInstances - ALLOWED" || \
  echo "❌ ec2:RunInstances - DENIED"

echo -e "\n2. Testing EC2:DescribeInstances..."
aws ec2 describe-instances --max-results 1 &>/dev/null && \
  echo "✅ ec2:DescribeInstances - ALLOWED" || \
  echo "❌ ec2:DescribeInstances - DENIED"

echo -e "\n3. Testing EC2:RequestSpotInstances (dry-run)..."
aws ec2 request-spot-instances \
  --spot-price "0.50" \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification '{
    "ImageId": "ami-0c55b159cbfafe1f0",
    "InstanceType": "g5.4xlarge"
  }' \
  --dry-run 2>&1 | grep -q "DryRunOperation" && \
  echo "✅ ec2:RequestSpotInstances - ALLOWED" || \
  echo "❌ ec2:RequestSpotInstances - DENIED"

echo -e "\n4. Testing EC2:CreateLaunchTemplate (dry-run)..."
aws ec2 create-launch-template \
  --launch-template-name test-permission-check \
  --version-description "test" \
  --launch-template-data '{"InstanceType":"t2.micro"}' \
  --dry-run 2>&1 | grep -q "DryRunOperation" && \
  echo "✅ ec2:CreateLaunchTemplate - ALLOWED" || \
  echo "❌ ec2:CreateLaunchTemplate - DENIED"

# Test 2: IAM Permissions
echo -e "\n5. Testing iam:ListRoles..."
aws iam list-roles --max-items 1 &>/dev/null && \
  echo "✅ iam:ListRoles - ALLOWED" || \
  echo "❌ iam:ListRoles - DENIED"

echo -e "\n6. Testing iam:CreateRole (test role)..."
aws iam create-role \
  --role-name test-permission-check-role-$RANDOM \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' &>/dev/null && \
  echo "✅ iam:CreateRole - ALLOWED (cleaning up...)" && \
  aws iam delete-role --role-name test-permission-check-role-* 2>/dev/null || \
  echo "❌ iam:CreateRole - DENIED"

echo -e "\n7. Testing iam:CreateInstanceProfile..."
aws iam create-instance-profile \
  --instance-profile-name test-permission-check-$RANDOM &>/dev/null && \
  echo "✅ iam:CreateInstanceProfile - ALLOWED (cleaning up...)" && \
  aws iam delete-instance-profile --instance-profile-name test-permission-check-* 2>/dev/null || \
  echo "❌ iam:CreateInstanceProfile - DENIED"

echo -e "\n8. Testing iam:ListInstanceProfiles..."
aws iam list-instance-profiles --max-items 1 &>/dev/null && \
  echo "✅ iam:ListInstanceProfiles - ALLOWED" || \
  echo "❌ iam:ListInstanceProfiles - DENIED"

# Test 3: Auto Scaling
echo -e "\n9. Testing autoscaling:DescribeAutoScalingGroups..."
aws autoscaling describe-auto-scaling-groups --max-records 1 &>/dev/null && \
  echo "✅ autoscaling:DescribeAutoScalingGroups - ALLOWED" || \
  echo "❌ autoscaling:DescribeAutoScalingGroups - DENIED"

echo -e "\n10. Testing autoscaling:CreateLaunchConfiguration..."
aws autoscaling create-launch-configuration \
  --launch-configuration-name test-permission-check-$RANDOM \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro 2>&1 | grep -q "already exists\|ValidationError\|created" && \
  echo "✅ autoscaling:CreateLaunchConfiguration - ALLOWED" || \
  echo "❌ autoscaling:CreateLaunchConfiguration - DENIED"

# Test 4: EventBridge/Scheduler
echo -e "\n11. Testing events:ListRules..."
aws events list-rules --max-results 1 &>/dev/null && \
  echo "✅ events:ListRules - ALLOWED" || \
  echo "❌ events:ListRules - DENIED"

echo -e "\n12. Testing events:PutRule..."
aws events put-rule \
  --name test-permission-check-$RANDOM \
  --schedule-expression "rate(1 day)" &>/dev/null && \
  echo "✅ events:PutRule - ALLOWED (cleaning up...)" && \
  aws events delete-rule --name test-permission-check-* 2>/dev/null || \
  echo "❌ events:PutRule - DENIED"

echo -e "\n13. Testing scheduler:ListSchedules..."
aws scheduler list-schedules --max-results 1 &>/dev/null && \
  echo "✅ scheduler:ListSchedules - ALLOWED" || \
  echo "❌ scheduler:ListSchedules - DENIED"

# Test 5: CloudWatch
echo -e "\n14. Testing cloudwatch:DescribeAlarms..."
aws cloudwatch describe-alarms --max-records 1 &>/dev/null && \
  echo "✅ cloudwatch:DescribeAlarms - ALLOWED" || \
  echo "❌ cloudwatch:DescribeAlarms - DENIED"

echo -e "\n15. Testing logs:DescribeLogGroups..."
aws logs describe-log-groups --limit 1 &>/dev/null && \
  echo "✅ logs:DescribeLogGroups - ALLOWED" || \
  echo "❌ logs:DescribeLogGroups - DENIED"

# Test 6: SSM (Alternative to Instance Profile)
echo -e "\n16. Testing ssm:DescribeInstanceInformation..."
aws ssm describe-instance-information --max-results 1 &>/dev/null && \
  echo "✅ ssm:DescribeInstanceInformation - ALLOWED" || \
  echo "❌ ssm:DescribeInstanceInformation - DENIED"

echo -e "\n======================================"
echo "Test Complete!"
echo "======================================"