#!/usr/bin/env bash
set -euo pipefail

# Required environment variables
: "${DEFECTDOJO_URL:?DEFECTDOJO_URL not set}"
: "${DEFECTDOJO_TOKEN:?DEFECTDOJO_TOKEN not set}"
: "${ENGAGEMENT_ID:?ENGAGEMENT_ID not set}"

upload_scan() {
  local scan_file="$1"
  local scan_type="$2"

  if [ ! -f "$scan_file" ] || [ ! -s "$scan_file" ]; then
    echo "[-] Scan file $scan_file not found or empty. Skipping."
    return 0
  fi

  echo "[+] Uploading $scan_file ($scan_type) to Engagement $ENGAGEMENT_ID..."
  
  HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
    -X POST "${DEFECTDOJO_URL%/}/api/v2/import-scan/" \
    -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
    -F "active=true" \
    -F "verified=true" \
    -F "scan_type=${scan_type}" \
    -F "engagement=${ENGAGEMENT_ID}" \
    -F "file=@${scan_file}")

  if [ "$HTTP_RESPONSE" -eq 201 ]; then
    echo "[✓] Successfully imported $scan_type (HTTP 201)."
  else
    echo "[!] Failed to import $scan_type. HTTP Code: $HTTP_RESPONSE"
    cat response.json
    echo ""
    return 1
  fi
}

# Example file mappings (adjust filenames to match your pipeline's outputs)
upload_scan "gitleaks-report.json" "Gitleaks Scan"
upload_scan "trivy-results.json" "Trivy Scan"
upload_scan "checkov-results.json" "Checkov Scan"