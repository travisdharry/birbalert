# BirbAlert AWS Infrastructure

This directory contains all AWS-related code for the BirbAlert cloud data pipeline and dashboard.

## Structure

```
aws/
├── lambda/                      # Lambda function code
│   ├── ingest_detection/       # POST endpoint - receives data from Pi
│   │   └── lambda_function.py
│   ├── query_detections/       # GET endpoint - serves data to dashboard
│   │   └── lambda_function.py
│   └── README.md               # Lambda deployment instructions
│
└── dashboard/                   # D3.js web dashboard
    ├── index.html
    ├── css/
    │   └── styles.css
    ├── js/
    │   ├── api.js              # API client
    │   ├── charts.js           # D3 visualizations
    │   └── main.js             # App logic
    └── README.md               # Dashboard deployment instructions
```

## Getting Started - Phase 1

Follow these steps in order:

### Step 1: Create DynamoDB Table

In AWS Console → DynamoDB → Create table:

**Table Configuration:**
- Table name: `BirdDetections`
- Partition key: `detection_id` (String)
- Sort key: `timestamp` (Number)
- Table settings: On-demand
- Enable encryption and point-in-time recovery

**Global Secondary Index (GSI):**
After table creation, add GSI:
- Index name: `date-timestamp-index`
- Partition key: `date` (String)
- Sort key: `timestamp` (Number)
- Projection type: All attributes

---

### Step 2: Deploy Lambda Functions

See `lambda/README.md` for detailed deployment instructions.

**Quick summary:**
1. Create `BirdNet-IngestDetection` function (Python 3.11)
2. Copy code from `lambda/ingest_detection/lambda_function.py`
3. Add DynamoDB write permissions
4. Create `BirdNet-QueryDetections` function (Python 3.11)
5. Copy code from `lambda/query_detections/lambda_function.py`
6. Add DynamoDB read permissions

---

### Step 3: Create API Gateway

In AWS Console → API Gateway → Create REST API:

**API Configuration:**
- API name: `BirdDetectionsAPI`
- Endpoint type: Regional

**Resources:**
1. Create resource: `/detections`
2. Create POST method → integrate with `BirdNet-IngestDetection`
3. Create GET method → integrate with `BirdNet-QueryDetections`
4. Enable CORS on `/detections`
5. Deploy to `prod` stage

**API Key (for Pi):**
1. Create API key: `raspberry-pi-key`
2. Create usage plan with throttling
3. Require API key on POST method
4. Deploy API again

**Save these values:**
- API Gateway URL: `https://[API-ID].execute-api.[REGION].amazonaws.com/prod`
- API Key: `[YOUR-KEY]`

---

### Step 4: Test the Backend

```bash
# Test POST (use your actual URL and API key)
curl -X POST "https://YOUR_API_URL/prod/detections" \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{
    "species": "Northern Cardinal",
    "confidence": 0.95,
    "timestamp": "2026-03-20T10:30:00-05:00",
    "alerted": true
  }'

# Test GET
curl "https://YOUR_API_URL/prod/detections?limit=10"
```

Check DynamoDB console to verify data was stored.

---

## Next Steps

After Phase 1 is complete:

- **Phase 2:** Update Raspberry Pi script to send data to AWS
- **Phase 3:** Test dashboard locally and update API URL
- **Phase 4:** Deploy dashboard to S3 + CloudFront

See `../AWS_PROJECT_PLAN.md` for complete instructions.

## Phase 4: S3 + CloudFront Deployment (Click-by-Click)

This checklist assumes your API is in `us-east-2` and your dashboard code is in `aws/dashboard/`.

### Step 1: Create S3 Bucket (Private)

1. AWS Console -> `S3` -> `Create bucket`
2. Bucket name: `birbalert-dashboard-<random>` (must be globally unique)
3. Region: `US East (Ohio) us-east-2`
4. Keep `Block all public access` enabled
5. Create bucket

### Step 2: Create CloudFront Distribution

1. AWS Console -> `CloudFront` -> `Create distribution`
2. Origin domain: select your S3 bucket (not website endpoint)
3. Origin access: `Origin access control settings (recommended)`
4. Click `Create new OAC`, accept defaults, save
5. Viewer protocol policy: `Redirect HTTP to HTTPS`
6. Allowed methods: `GET, HEAD`
7. Cache policy: `CachingOptimized`
8. Default root object: `index.html`
9. Price class: `Use only North America and Europe` (lower cost)
10. Create distribution

### Step 3: Attach Bucket Policy for OAC

1. In CloudFront distribution setup, copy the suggested bucket policy
2. Go to `S3` -> your bucket -> `Permissions` -> `Bucket policy`
3. Paste policy and save

### Step 4: Upload Dashboard Files

1. Go to `S3` -> your dashboard bucket -> `Upload`
2. Upload contents of `aws/dashboard/`:
  - `index.html`
  - `css/`
  - `js/`
3. Complete upload

### Step 5: Verify Deployment

1. Wait for CloudFront status to become `Deployed`
2. Open CloudFront distribution domain URL
3. Confirm dashboard loads and charts request data successfully

If you see stale files or 403s:

1. CloudFront -> your distribution -> `Invalidations` -> `Create invalidation`
2. Path: `/*`
3. Create invalidation and retry

### Step 6: Tighten API CORS

After dashboard is live, restrict CORS from `*` to your CloudFront domain:

1. AWS Console -> `API Gateway` -> `BirdDetectionsAPI`
2. Update `Access-Control-Allow-Origin` for `GET /detections` and `POST /detections`
3. Set to `https://<your-cloudfront-domain>`
4. Redeploy API to `prod`

### Step 7: Rotate API Key

Your API key has been used in local files and terminal history. Rotate it:

1. Create new API key in API Gateway
2. Attach it to usage plan
3. Update `raspberry_pi/config.yaml` with new key
4. Restart `birdnet` service on Pi
5. Disable old key

### Optional: Custom Domain (IONOS)

Use this to serve the dashboard at `https://birbalert.clinkeranalytics.com`.

1. Request an ACM certificate in `us-east-1`:
  - AWS Console -> `Certificate Manager` (region must be `us-east-1` for CloudFront)
  - Request public certificate for `birbalert.clinkeranalytics.com`
  - Validation method: DNS

2. Add ACM validation CNAME in IONOS:
  - In ACM, copy the DNS validation `Name` and `Value`
  - In IONOS DNS, create that CNAME record exactly
  - Wait for ACM certificate status `Issued`

3. Attach custom domain in CloudFront:
  - CloudFront -> your distribution -> `Edit`
  - Alternate domain name (CNAME): `birbalert.clinkeranalytics.com`
  - Custom SSL certificate: select the ACM cert from step 1
  - Save changes and wait for deployment

4. Create IONOS DNS record for dashboard hostname:
  - Record type: `CNAME`
  - Host/Name: `birbalert`
  - Target/Value: `<your-cloudfront-distribution-domain>` (for example `dxxxxxxxxxxxx.cloudfront.net`)

5. Verify over HTTPS:
  - Open `https://birbalert.clinkeranalytics.com`
  - If stale content appears, create CloudFront invalidation `/*`

6. Tighten API CORS after domain is live:
  - Replace `Access-Control-Allow-Origin: *` with `https://birbalert.clinkeranalytics.com`
  - Redeploy API to `prod`

## AWS Region

Recommend using `us-east-1` for:
- Lowest cost
- Best CloudFront integration
- Most service availability

All resources should be in the same region.

## Tagging

Tag all resources with:
- `Project: BirbAlert`
- `Environment: Personal`
- `ManagedBy: Manual` (or `Terraform` if you automate later)

This helps with cost tracking and organization.
