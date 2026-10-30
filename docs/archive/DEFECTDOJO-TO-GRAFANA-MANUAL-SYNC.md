# DefectDojo to Grafana Manual Sync Guide

## Overview
This guide explains how to manually pull vulnerability findings from DefectDojo and visualize them in Grafana dashboards.

## Prerequisites
- DefectDojo running (e.g., `http://localhost:8000`)
- Prometheus Pushgateway (`http://localhost:9091`)
- Prometheus configured to scrape Pushgateway
- Grafana connected to Prometheus (`http://localhost:3000`)

## Step 1: Get Your DefectDojo API Key

### From DefectDojo UI:
1. Log in to DefectDojo: `http://localhost:8000`
2. Click your **Username** (top-right) → **API v2 Token**
3. Copy your API token (looks like: `abcd1234efgh5678ijkl9012`)

### Via CLI:
```bash
# If you have admin access, create a token for automation
curl -X POST http://localhost:8000/api/v2/api-token-auth/ \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your_password"}'
```

## Step 2: Run Manual Sync Script

### Option A: One-time sync
```bash
chmod +x ./scripts/defectdojo-to-grafana.sh

./scripts/defectdojo-to-grafana.sh \
  http://localhost:8000 \
  your-api-key \
  http://localhost:9091 \
  "Secure DevOps Pipeline"
```

### Option B: Automated sync (cron job)
```bash
# Edit crontab
crontab -e

# Add this line to sync every 30 minutes:
*/30 * * * * cd /path/to/secure-devops-pipeline && ./scripts/defectdojo-to-grafana.sh http://localhost:8000 $DEFECTDOJO_API_KEY http://localhost:9091 "Secure DevOps Pipeline"
```

### Option C: Scheduled via GitHub Actions (recommended for CI/CD)
```yaml
name: Sync DefectDojo to Grafana

on:
  schedule:
    # Run every hour at minute 0
    - cron: '0 * * * *'
  workflow_dispatch:  # Manual trigger

jobs:
  sync:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4.1.7
      
      - name: Sync DefectDojo to Grafana
        run: |
          chmod +x ./scripts/defectdojo-to-grafana.sh
          ./scripts/defectdojo-to-grafana.sh \
            "${{ secrets.DEFECTDOJO_URL }}" \
            "${{ secrets.DEFECTDOJO_API_KEY }}" \
            "${{ secrets.PUSHGATEWAY_URL }}" \
            "Secure DevOps Pipeline"
```

## Step 3: Create Grafana Dashboard

### Using Metrics in Grafana:

1. **Log in to Grafana**: `http://localhost:3000` (default: admin/admin)

2. **Create new dashboard**: Click **+** → **Dashboard**

3. **Add panel for Critical Findings**:
   - Click **Add a new panel**
   - In **Metrics browser**, search: `defectdojo_findings_critical`
   - Set visualization: **Gauge** or **Stat**
   - Title: "Critical Vulnerabilities"
   - Save

4. **Add panel for High Findings**:
   - Same as above, use: `defectdojo_findings_high`
   - Title: "High Vulnerabilities"

5. **Add Time Series Panel**:
   - Use PromQL query:
   ```promql
   defectdojo_findings_critical
   + defectdojo_findings_high
   + defectdojo_findings_medium
   + defectdojo_findings_low
   ```
   - Title: "Total Findings Over Time"
   - Visualization: **Time Series**

## Step 4: API Query Examples

### Get All Findings for a Product:
```bash
PRODUCT_ID=1
curl -H "Authorization: Token YOUR_API_KEY" \
  "http://localhost:8000/api/v2/findings/?product=$PRODUCT_ID&active=true"
```

### Get Critical Findings Only:
```bash
curl -H "Authorization: Token YOUR_API_KEY" \
  "http://localhost:8000/api/v2/findings/?product=1&severity=Critical&active=true"
```

### Get Tests and Scans:
```bash
curl -H "Authorization: Token YOUR_API_KEY" \
  "http://localhost:8000/api/v2/tests/?engagement__product=1"
```

## Troubleshooting

### Connection Refused
**Problem**: `curl: (7) Failed to connect to localhost port 8000`
**Solution**: 
- Ensure DefectDojo is running: `docker ps | grep defectdojo`
- If using Docker Compose, check: `docker-compose logs defectdojo`
- For self-hosted runner, use host IP instead of localhost: `http://192.168.x.x:8000`

### Authentication Failed
**Problem**: 401 Unauthorized errors
**Solution**:
- Verify API token is correct: `curl -H "Authorization: Token YOUR_KEY" http://localhost:8000/api/v2/products/`
- Check token hasn't expired in DefectDojo UI
- Regenerate token if needed

### No Data in Grafana
**Problem**: Prometheus doesn't show metrics
**Solution**:
1. Verify Pushgateway received metrics:
   ```bash
   curl http://localhost:9091/metrics | grep defectdojo
   ```
2. Check Prometheus config includes Pushgateway:
   ```yaml
   scrape_configs:
     - job_name: 'pushgateway'
       static_configs:
         - targets: ['localhost:9091']
   ```
3. Verify Prometheus has scraped: `http://localhost:9090` → **Status** → **Targets**

## Advanced: Custom PromQL Queries

### Total Vulnerabilities:
```promql
defectdojo_findings_critical + defectdojo_findings_high + defectdojo_findings_medium + defectdojo_findings_low
```

### Critical + High Trend:
```promql
defectdojo_findings_critical + defectdojo_findings_high
```

### Vulnerability Percentage (High Severity):
```promql
defectdojo_findings_high / 
(defectdojo_findings_critical + defectdojo_findings_high + defectdojo_findings_medium + defectdojo_findings_low) * 100
```

## Integration with CI/CD Pipeline

Add to your workflow after security scans:

```yaml
- name: Manual DefectDojo Sync to Grafana
  if: always()
  run: |
    chmod +x ./scripts/defectdojo-to-grafana.sh
    ./scripts/defectdojo-to-grafana.sh \
      "${{ secrets.DEFECTDOJO_URL }}" \
      "${{ secrets.DEFECTDOJO_API_KEY }}" \
      "${{ secrets.PUSHGATEWAY_URL }}" \
      "Secure DevOps Pipeline"
```

## Why Manual Sync Over Automatic?

✅ **Advantages of manual/scheduled approach**:
- More reliable (doesn't depend on webhooks)
- Control over when data syncs
- Can retry on failure
- Works with on-prem DefectDojo
- Supports multiple products
- Custom metric calculations

❌ **Webhook limitations**:
- DefectDojo might not send webhooks properly
- Requires firewall rules for incoming connections
- Can miss events if webhook delivery fails
- Limited to finding creation/update events

---

**Need help?** Check DefectDojo logs:
```bash
docker logs defectdojo
```

Or Prometheus logs:
```bash
docker logs prometheus
```
