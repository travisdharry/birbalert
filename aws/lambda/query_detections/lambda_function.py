import json
import boto3
from boto3.dynamodb.conditions import Attr
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('BirdDetections')

CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': 'https://birbalert.clinkeranalytics.com'
}

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    """
    Query bird detections for dashboard
    Supports: date range, species filter, aggregations
    """
    try:
        # Parse query parameters
        params = event.get('queryStringParameters', {}) or {}
        start_date = params.get('start_date')
        end_date = params.get('end_date')
        species = params.get('species')
        limit = max(1, min(int(params.get('limit', 1000)), 5000))

        # NOTE: The current GSI has date as partition key, which supports date equality,
        # not a date range across partitions. For dashboard date-range requests we use a
        # filtered scan and stop once we collect the requested limit.
        scan_kwargs = {}
        filters = []

        if start_date:
            filters.append(Attr('date').between(start_date, end_date or start_date))
        if species:
            filters.append(Attr('species').eq(species))

        if filters:
            filter_expr = filters[0]
            for expr in filters[1:]:
                filter_expr = filter_expr & expr
            scan_kwargs['FilterExpression'] = filter_expr

        items = []
        last_key = None
        while len(items) < limit:
            if last_key:
                scan_kwargs['ExclusiveStartKey'] = last_key
            # Scan in chunks to avoid over-fetching and allow pagination.
            response = table.scan(Limit=min(500, limit), **scan_kwargs)
            items.extend(response.get('Items', []))
            last_key = response.get('LastEvaluatedKey')
            if not last_key:
                break

        items = items[:limit]

        # Keep output stable for UI by ordering newest first.
        items.sort(key=lambda i: i.get('timestamp', 0), reverse=True)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'count': len(items),
                'detections': items
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': str(e)})
        }
