#!/usr/bin/env bash
set -euo pipefail

REPORTS_DIR="${1:-.}"
BASE_URL="${DEFECTDOJO_URL%/}"
PRODUCT_NAME="${DEFECTDOJO_PRODUCT_NAME:-Secure DevOps Pipeline}"
ENGAGEMENT_NAME="${DEFECTDOJO_ENGAGEMENT_NAME:-CI/CD Automated Scan}"

echo "=== DefectDojo Ingestion Manager (Direct Runner Connection) ==="
echo "[+] Target Host: $BASE_URL"
echo "[+] Reports Directory: $REPORTS_DIR"

# 1. Fetch or Create Product
PRODUCT_ID=$(curl -s -G "${BASE_URL}/api/v2/products/" \
  -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
  --data-urlencode "name=${PRODUCT_NAME}" | jq -r '.results[0].id // empty')

if [ -z "$PRODUCT_ID" ]; then
  PRODUCT_ID=$(curl -s -X POST "${BASE_URL}/api/v2/products/" \
    -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${PRODUCT_NAME}\", \"description\": \"Automated CI/CD security findings\", \"prod_type\": 1}" \
    | jq -r '.id')
fi
echo "[✓] Product ID: $PRODUCT_ID"

# 2. Fetch or Create Active Engagement
ENGAGEMENT_ID=$(curl -s -G "${BASE_URL}/api/v2/engagements/" \
  -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
  --data-urlencode "product=${PRODUCT_ID}" \
  --data-urlencode "name=${ENGAGEMENT_NAME}" \
  --data-urlencode "status=In Progress" | jq -r '.results[0].id // empty')

if [ -z "$ENGAGEMENT_ID" ]; then
  TODAY=$(date +%Y-%m-%d)
  ENGAGEMENT_ID=$(curl -s -X POST "${BASE_URL}/api/v2/engagements/" \
    -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ENGAGEMENT_NAME}\",
      \"product\": ${PRODUCT_ID},
      \"target_start\": \"${TODAY}\",
      \"target_end\": \"2030-01-01\",
      \"status\": \"In Progress\",
      \"engagement_type\": \"CI/CD\"
    }" | jq -r '.id')
fi
echo "[✓] Engagement ID: $ENGAGEMENT_ID"

# 3. Upload Function
upload_scan() {
  local scan_file="$REPORTS_DIR/$1"
  local scan_type="$2"

  if [ ! -f "$scan_file" ] || [ ! -s "$scan_file" ]; then
    echo "[-] File '$scan_file' missing or empty. Skipping $scan_type."
    return 0
  fi

  echo "[+] Uploading $scan_file ($scan_type)..."
  HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/dd_response.json \
    -X POST "${BASE_URL}/api/v2/import-scan/" \
    -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
    -F "active=true" \
    -F "verified=true" \
    -F "minimum_severity=Info" \
    -F "scan_type=${scan_type}" \
    -F "engagement=${ENGAGEMENT_ID}" \
    -F "file=@${scan_file}")

  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "[✓] Imported $scan_type successfully (HTTP 201)."
  else
    echo "[!] Error uploading $scan_type (HTTP $HTTP_CODE):"
    cat /tmp/dd_response.json
    echo ""
  fi
}

# 4. Ingest All Upload Artifacts
upload_scan "gitleaks-report.json" "Gitleaks Scan"
upload_scan "trivy-sca-results.json" "Trivy Scan"
upload_scan "checkov-results.json" "Checkov Scan"
upload_scan "grype-results.json" "Anchore Grype"
upload_scan "zap-results.json" "ZAP Scan"