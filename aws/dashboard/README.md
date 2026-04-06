# BirbAlert Dashboard

Interactive D3.js dashboard for visualizing bird detection data.

## Local Testing

Before deploying to AWS, test the dashboard locally:

```bash
cd aws/dashboard
python3 -m http.server 8000
```

Open http://localhost:8000 in your browser.

**Note:** The dashboard won't load data until you:
1. Complete Phase 1 (DynamoDB + Lambda + API Gateway)
2. Update the API URL in `js/api.js`

## Configuration

Edit `js/api.js` and replace:
```javascript
const API_BASE = 'https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod';
```

With your actual API Gateway URL from Phase 1.

## Features

- **Species Bar Chart** - Top 15 most detected species
- **Timeline Chart** - Daily detection counts over time
- **Hour Heatmap** - Activity patterns by hour of day
- **Stats Cards** - Total detections, unique species, top bird, avg confidence
- **Recent Table** - Last 50 detections with details
- **Date Filters** - Query specific date ranges
- **Auto-refresh** - Updates every 5 minutes

## Deployment (Phase 4)

After testing locally, deploy to AWS:

1. Create S3 bucket for static website hosting
2. Upload all files to the bucket
3. Create CloudFront distribution for HTTPS
4. (Optional) Configure custom domain

See AWS_PROJECT_PLAN.md Phase 4 for detailed instructions.

## Tech Stack

- D3.js v7 (data visualization)
- Vanilla JavaScript (no framework)
- CSS Grid/Flexbox (responsive layout)
- ES6 Modules
