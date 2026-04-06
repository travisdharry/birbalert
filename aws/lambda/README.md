# Lambda Deployment Instructions

## For Each Lambda Function

Both Lambda functions are ready to deploy. Here's how:

### 1. ingest_detection (POST endpoint)
**Location:** `aws/lambda/ingest_detection/lambda_function.py`

**Deploy via AWS Console:**
1. Go to AWS Lambda → Create function
2. Name: `BirdNet-IngestDetection`
3. Runtime: Python 3.11
4. Create function
5. Copy the entire contents of `lambda_function.py` into the code editor
6. Configuration:
   - Timeout: 10 seconds
   - Memory: 256 MB
   - Environment variable: `TABLE_NAME=BirdDetections`
7. Add DynamoDB permissions to the execution role:
   - Go to Configuration → Permissions
   - Click the role name
   - Add inline policy allowing `dynamodb:PutItem` on `BirdDetections` table

### 2. query_detections (GET endpoint)
**Location:** `aws/lambda/query_detections/lambda_function.py`

**Deploy via AWS Console:**
1. Go to AWS Lambda → Create function
2. Name: `BirdNet-QueryDetections`
3. Runtime: Python 3.11
4. Create function
5. Copy the entire contents of `lambda_function.py` into the code editor
6. Configuration:
   - Timeout: 10 seconds
   - Memory: 256 MB
   - Environment variable: `TABLE_NAME=BirdDetections`
7. Add DynamoDB permissions to the execution role:
   - Go to Configuration → Permissions
   - Click the role name
   - Add inline policy allowing `dynamodb:Query` and `dynamodb:Scan` on `BirdDetections` table and its indexes

## IAM Policy Examples

### For ingest_detection (Write access):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "dynamodb:PutItem",
    "Resource": "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/BirdDetections"
  }]
}
```

### For query_detections (Read access):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["dynamodb:Query", "dynamodb:Scan"],
    "Resource": [
      "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/BirdDetections",
      "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/BirdDetections/index/*"
    ]
  }]
}
```

Replace `REGION` with your AWS region (e.g., `us-east-1`) and `ACCOUNT_ID` with your AWS account ID.
