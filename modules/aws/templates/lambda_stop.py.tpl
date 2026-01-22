"""
Lambda function to stop GPU instances
Triggered by EventBridge at Ethiopia Time 6:00 PM (15:00 UTC)
"""
import boto3
import logging
import os
import json
from datetime import datetime

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level))

# Environment variables
ASG_NAME = os.environ.get('ASG_NAME', '${asg_name}')
PROJECT_NAME = os.environ.get('PROJECT_NAME', '${project_name}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', '${environment}')

# AWS clients
ec2 = boto3.client('ec2')
autoscaling = boto3.client('autoscaling')


def lambda_handler(event, context):
    """
    Main handler for stopping GPU instances
    """
    logger.info(f"Stopping GPU instances for {PROJECT_NAME}-{ENVIRONMENT}")
    logger.info(f"Event: {json.dumps(event)}")
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'stop',
        'asg_name': ASG_NAME,
        'instances_stopped': [],
        'errors': []
    }
    
    try:
        # Method 1: Update ASG desired capacity to 0
        update_asg_capacity(results)
        
        # Method 2: Stop specific instances (backup)
        stop_tagged_instances(results)
        
        logger.info(f"Results: {json.dumps(results)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results)
        }
        
    except Exception as e:
        error_msg = f"Error stopping instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps(results)
        }


def update_asg_capacity(results):
    """
    Update Auto Scaling Group desired capacity to 0 to stop instances
    """
    try:
        # Get current ASG configuration
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[ASG_NAME]
        )
        
        if not response['AutoScalingGroups']:
            logger.warning(f"ASG {ASG_NAME} not found")
            results['errors'].append(f"ASG {ASG_NAME} not found")
            return
        
        asg = response['AutoScalingGroups'][0]
        current_desired = asg['DesiredCapacity']
        current_min = asg['MinSize']
        
        logger.info(f"Current ASG state - Desired: {current_desired}, Min: {current_min}")
        
        # First, update min size to 0 if needed
        if current_min > 0:
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=ASG_NAME,
                MinSize=0
            )
            logger.info(f"Updated ASG min size from {current_min} to 0")
        
        # Then set desired capacity to 0
        if current_desired > 0:
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=ASG_NAME,
                DesiredCapacity=0
            )
            
            logger.info(f"Updated ASG desired capacity from {current_desired} to 0")
            results['asg_updated'] = True
            results['previous_desired'] = current_desired
            results['new_desired'] = 0
        else:
            logger.info("ASG already has desired capacity of 0")
            results['asg_updated'] = False
            
    except Exception as e:
        error_msg = f"Error updating ASG: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)


def stop_tagged_instances(results):
    """
    Stop instances with specific tags (backup method)
    """
    try:
        # Find running instances with our tags
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]},
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:GPUInstance', 'Values': ['true']},
                {'Name': 'instance-state-name', 'Values': ['running', 'pending']}
            ]
        )
        
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
        
        if not instance_ids:
            logger.info("No running GPU instances found")
            return
        
        logger.info(f"Found {len(instance_ids)} running instances: {instance_ids}")
        
        # Stop instances
        ec2.stop_instances(InstanceIds=instance_ids)
        
        logger.info(f"Stopped instances: {instance_ids}")
        results['instances_stopped'] = instance_ids
        
    except Exception as e:
        error_msg = f"Error stopping tagged instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
