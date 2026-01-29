#!/bin/bash

echo "======================================"
echo "Testing Critical Permissions"
echo "======================================"

ARN=$(aws sts get-caller-identity --query 'Arn' --output text)

echo -e "\n1. Testing EC2 Permissions (claiming full access)..."
aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names \
    ec2:RunInstances \
    ec2:StartInstances \
    ec2:StopInstances \
    ec2:TerminateInstances \
    ec2:RequestSpotInstances \
    ec2:CreateLaunchTemplate \
    ec2:CreateTags \
  --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
  --output table

echo -e "\n2. Testing Critical IAM PassRole..."
aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names iam:PassRole \
  --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
  --output table

echo -e "\n3. Testing Auto Scaling..."
aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names \
    autoscaling:CreateAutoScalingGroup \
    autoscaling:UpdateAutoScalingGroup \
    autoscaling:SetDesiredCapacity \
  --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
  --output table

echo -e "\n4. Testing EventBridge/Scheduler..."
aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names \
    events:PutRule \
    events:PutTargets \
    scheduler:CreateSchedule \
  --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
  --output table

echo -e "\n5. Testing CloudWatch..."
aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names \
    cloudwatch:PutMetricAlarm \
    logs:CreateLogGroup \
    logs:CreateLogStream \
  --query 'EvaluationResults[*].[ActionName, EvalDecision]' \
  --output table

echo -e "\n======================================"
echo "Test Complete!"
echo "======================================"