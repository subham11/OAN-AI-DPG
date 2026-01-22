"""
GCP Cloud Function to stop GPU instances
Triggered by Cloud Scheduler at Ethiopia Time 6:00 PM (15:00 UTC)
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


def stop_instances(request):
    """
    Main handler for stopping GPU instances via MIG resize to 0.
    """
    logger.info(f"Stopping GPU instances for MIG: {MIG_NAME}")
    logger.info(f"Project: {PROJECT_ID}, Region: {REGION}")
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'action': 'stop',
        'mig_name': MIG_NAME,
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
        
        if current_size > 0:
            # Resize MIG to 0
            logger.info(f"Resizing MIG from {current_size} to 0")
            
            operation = mig_client.resize(
                project=PROJECT_ID,
                region=REGION,
                instance_group_manager=MIG_NAME,
                size=0
            )
            
            logger.info(f"Resize operation started: {operation.name}")
            results['operation'] = operation.name
            results['new_size'] = 0
            results['status'] = 'stopping'
        else:
            logger.info("MIG already has 0 instances")
            results['status'] = 'no_change'
        
        logger.info(f"Results: {json.dumps(results)}")
        
        return (json.dumps(results), 200, {'Content-Type': 'application/json'})
        
    except Exception as e:
        error_msg = f"Error stopping instances: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
        results['status'] = 'error'
        
        return (json.dumps(results), 500, {'Content-Type': 'application/json'})
