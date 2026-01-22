"""
GCP Cloud Function to start GPU instances
Triggered by Cloud Scheduler at IST 9:30 AM (04:00 UTC)
"""
import os
import logging
import json
from datetime import datetime
from google.cloud import compute_v1

# Configure logging
logging.basicConfig(level=os.environ.get('LOG_LEVEL', 'INFO'))
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
MIG_NAME = os.environ.get('MIG_NAME', '${mig_name}')
TARGET_SIZE = int(os.environ.get('TARGET_SIZE', '${target_size}'))


def start_instances(request):
    """
    Main handler for starting GPU instances via MIG resize.
    """
    logger.info(f"Starting GPU instances for MIG: {MIG_NAME}")
    logger.info(f"Project: {PROJECT_ID}, Region: {REGION}")
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'start',
        'mig_name': MIG_NAME,
        'target_size': TARGET_SIZE,
        'errors': []
    }
    
    try:
        # Create MIG client
        mig_client = compute_v1.RegionInstanceGroupManagersClient()
        
        # Get current MIG state
        mig = mig_client.get(
            project=PROJECT_ID,
            region=REGION,
            instance_group_manager=MIG_NAME
        )
        
        current_size = mig.target_size
        logger.info(f"Current MIG size: {current_size}")
        results['previous_size'] = current_size
        
        if current_size < TARGET_SIZE:
            # Resize MIG to target size
            logger.info(f"Resizing MIG from {current_size} to {TARGET_SIZE}")
            
            operation = mig_client.resize(
                project=PROJECT_ID,
                region=REGION,
                instance_group_manager=MIG_NAME,
                size=TARGET_SIZE
            )
            
            logger.info(f"Resize operation started: {operation.name}")
            results['operation'] = operation.name
            results['new_size'] = TARGET_SIZE
            results['status'] = 'resizing'
        else:
            logger.info(f"MIG already has {current_size} instances, no resize needed")
            results['status'] = 'no_change'
        
        logger.info(f"Results: {json.dumps(results)}")
        
        return (json.dumps(results), 200, {'Content-Type': 'application/json'})
        
    except Exception as e:
        error_msg = f"Error starting instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
        results['status'] = 'error'
        
        return (json.dumps(results), 500, {'Content-Type': 'application/json'})
