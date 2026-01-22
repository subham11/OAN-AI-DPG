"""
Lambda function to start GPU instances
Triggered by EventBridge at IST 9:30 AM (04:00 UTC)
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
    Main handler for starting GPU instances
    """
    logger.info(f"Starting GPU instances for {PROJECT_NAME}-{ENVIRONMENT}")
    logger.info(f"Event: {json.dumps(event)}")
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'start',
        'asg_name': ASG_NAME,
        'instances_started': [],
        'errors': []
    }
    
    try:
        # Method 1: Update ASG desired capacity
        update_asg_capacity(results)
        
        # Method 2: Start specific instances (backup)
        start_tagged_instances(results)
        
        logger.info(f"Results: {json.dumps(results)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results)
        }
        
    except Exception as e:
        error_msg = f"Error starting instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps(results)
        }


def update_asg_capacity(results):
    """
    Update Auto Scaling Group desired capacity to start instances
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
        min_size = asg['MinSize']
        
        logger.info(f"Current ASG state - Desired: {current_desired}, Min: {min_size}")
        
        # If desired is 0 or less than min, set to min
        if current_desired < min_size or current_desired == 0:
            new_desired = max(min_size, 1)  # At least 1 instance
            
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=ASG_NAME,
                DesiredCapacity=new_desired
            )
            
            logger.info(f"Updated ASG desired capacity from {current_desired} to {new_desired}")
            results['asg_updated'] = True
            results['previous_desired'] = current_desired
            results['new_desired'] = new_desired
        else:
            logger.info(f"ASG already has desired capacity of {current_desired}")
            results['asg_updated'] = False
            
    except Exception as e:
        error_msg = f"Error updating ASG: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)


def start_tagged_instances(results):
    """
    Start instances with specific tags (backup method)
    """
    try:
        # Find stopped instances with our tags
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]},
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:GPUInstance', 'Values': ['true']},
                {'Name': 'instance-state-name', 'Values': ['stopped']}
            ]
        )
        
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
        
        if not instance_ids:
            logger.info("No stopped GPU instances found")
            return
        
        logger.info(f"Found {len(instance_ids)} stopped instances: {instance_ids}")
        
        # Start instances
        ec2.start_instances(InstanceIds=instance_ids)
        
        logger.info(f"Started instances: {instance_ids}")
        results['instances_started'] = instance_ids
        
    except Exception as e:
        error_msg = f"Error starting tagged instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
