import json
import boto3
import uuid
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('BirdDetections')

ALLOWED_ORIGIN = 'https://birbalert.clinkeranalytics.com'
CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': ALLOWED_ORIGIN
}

def lambda_handler(event, context):
    """
    Receives bird detection from Raspberry Pi via API Gateway
    Validates data and stores in DynamoDB
    """
    try:
        # Parse incoming data
        body = json.loads(event['body'])
        
        # Validate required fields
        required = ['species', 'confidence', 'timestamp']
        if not all(k in body for k in required):
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Missing required fields'})
            }
        
        # Parse timestamp
        ts = datetime.fromisoformat(body['timestamp'].replace('Z', '+00:00'))
        
        # Prepare item
        item = {
            'detection_id': str(uuid.uuid4()),
            'timestamp': int(ts.timestamp()),
            'date': ts.strftime('%Y-%m-%d'),
            'hour': ts.hour,
            'species': body['species'],
            'confidence': Decimal(str(body['confidence'])),
            'alerted': body.get('alerted', True),
            'raw_data': json.dumps(body)  # Store full payload for debugging
        }
        
        # Write to DynamoDB
        table.put_item(Item=item)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'success': True,
                'detection_id': item['detection_id']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': str(e)})
        }
