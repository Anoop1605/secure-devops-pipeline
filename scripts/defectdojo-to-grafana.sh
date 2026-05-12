#!/bin/bash
# DefectDojo to Grafana sync script.
# Pulls findings from DefectDojo API and pushes dashboard-compatible metrics to Pushgateway.

set -euo pipefail

DEFECTDOJO_URL="http://localhost:8000"
DEFECTDOJO_API_KEY=""
PUSHGATEWAY_URL="http://localhost:9091"
PRODUCT_NAME="Secure DevOps Pipeline"

usage() {
  echo "Usage: $0 --url <defectdojo_url> --api-key <token> [--pushgateway <url>] [--product <name>]"
  echo ""
  echo "Example:"
  echo "  $0 --url http://localhost:8000 --api-key YOUR_TOKEN --pushgateway http://localhost:9091 --product \"Secure DevOps Pipeline\""
}

# Support both named and positional args.
positionals=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      DEFECTDOJO_URL="$2"
      shift 2
      ;;
    --api-key)
      DEFECTDOJO_API_KEY="$2"
      shift 2
      ;;
    --pushgateway)
      PUSHGATEWAY_URL="$2"
      shift 2
      ;;
    --product)
      PRODUCT_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [[ ${#positionals[@]} -gt 0 ]]; then
  [[ ${#positionals[@]} -ge 1 ]] && DEFECTDOJO_URL="${positionals[0]}"
  [[ ${#positionals[@]} -ge 2 ]] && DEFECTDOJO_API_KEY="${positionals[1]}"
  [[ ${#positionals[@]} -ge 3 ]] && PUSHGATEWAY_URL="${positionals[2]}"
  [[ ${#positionals[@]} -ge 4 ]] && PRODUCT_NAME="${positionals[3]}"
fi

if [[ -z "$DEFECTDOJO_API_KEY" ]]; then
  echo "ERROR: API key is required."
  usage
  exit 1
fi

DEFECTDOJO_URL="${DEFECTDOJO_URL%/}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL%/}"
AUTH_HEADER="Authorization: Token $DEFECTDOJO_API_KEY"
DEFECTDOJO_API="$DEFECTDOJO_URL/api/v2"

echo "==============================================================="
echo "DefectDojo -> Grafana Data Sync"
echo "==============================================================="
echo "DefectDojo URL: $DEFECTDOJO_URL"
echo "Pushgateway URL: $PUSHGATEWAY_URL"
echo "Product: $PRODUCT_NAME"
echo ""

echo "[0/4] Checking API and Pushgateway connectivity..."
api_code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$DEFECTDOJO_API/products/?limit=1")
pg_code=$(curl -s -o /dev/null -w "%{http_code}" "$PUSHGATEWAY_URL/metrics")
if [[ "$api_code" != "200" ]]; then
  echo "ERROR: DefectDojo API not reachable or unauthorized (HTTP $api_code)."
  exit 1
fi
if [[ "$pg_code" != "200" ]]; then
  echo "ERROR: Pushgateway not reachable (HTTP $pg_code)."
  exit 1
fi

echo "[1/4] Resolving product id..."
product_resp=$(curl -s -G -H "$AUTH_HEADER" --data-urlencode "name=$PRODUCT_NAME" "$DEFECTDOJO_API/products/")
product_id=$(echo "$product_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['id'] if d.get('results') else '')")
if [[ -z "$product_id" ]]; then
  echo "ERROR: Product not found: $PRODUCT_NAME"
  exit 1
fi
echo "Product id: $product_id"

echo "[2/4] Pulling findings..."
findings_json=$(curl -s -H "$AUTH_HEADER" "$DEFECTDOJO_API/findings/?product=$product_id&active=true&limit=1000")

echo "[3/4] Building dashboard-compatible metrics..."
tmp_findings_file=$(mktemp)
printf '%s' "$findings_json" > "$tmp_findings_file"
metrics_payload=$(python3 - "$tmp_findings_file" <<'PY'
import json
import sys
from collections import Counter
from datetime import datetime, timezone

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
rows = data.get("results", []) or []

severity_map = {"critical": 0, "high": 0, "medium": 0, "low": 0}
tool_counts = Counter()
cvss_ranges = {"0-3": 0, "4-6": 0, "7-8": 0, "9-10": 0}
mttd_values = []

def parse_dt(value):
    if not value:
        return None
    value = value.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None

for f in rows:
    sev = str(f.get("severity", "")).strip().lower()
    if sev in severity_map:
        severity_map[sev] += 1

    tool = (
        f.get("test_name")
        or f.get("scanner_conf")
        or f.get("title")
        or "unknown"
    )
    tool = str(tool).replace('\\', '').replace('"', "'")
    tool = tool.replace("\n", " ").replace("\r", " ").strip()
    if not tool:
      tool = "unknown"
    tool_counts[tool] += 1

    score = f.get("cvssv3")
    if score in (None, ""):
        score = f.get("cvss")
    try:
        score = float(score)
    except Exception:
        score = 0.0
    if score < 4:
        cvss_ranges["0-3"] += 1
    elif score < 7:
        cvss_ranges["4-6"] += 1
    elif score < 9:
        cvss_ranges["7-8"] += 1
    else:
        cvss_ranges["9-10"] += 1

    # Approximate MTTD as created - discovered date when available.
    created = parse_dt(f.get("created"))
    discovered = parse_dt(f.get("date"))
    if created and discovered:
        delta = (created - discovered).total_seconds()
        if delta >= 0:
            mttd_values.append(delta)

total_findings = len(rows)
critical = severity_map["critical"]
high = severity_map["high"]
medium = severity_map["medium"]
low = severity_map["low"]
avg_mttd = sum(mttd_values) / len(mttd_values) if mttd_values else 0.0

lines = []
lines.append("# TYPE dd_findings_total gauge")
lines.append(f"dd_findings_total {total_findings}")

lines.append("# TYPE dd_findings_critical_total gauge")
lines.append(f"dd_findings_critical_total {critical}")
lines.append("# TYPE dd_findings_high_total gauge")
lines.append(f"dd_findings_high_total {high}")
lines.append("# TYPE dd_findings_medium_total gauge")
lines.append(f"dd_findings_medium_total {medium}")
lines.append("# TYPE dd_findings_low_total gauge")
lines.append(f"dd_findings_low_total {low}")

lines.append("# TYPE dd_findings_by_severity gauge")
for k in ("critical", "high", "medium", "low"):
    lines.append(f'dd_findings_by_severity{{severity="{k.upper()}"}} {severity_map[k]}')

lines.append("# TYPE dd_findings_by_tool gauge")
for tool, count in sorted(tool_counts.items()):
    lines.append(f'dd_findings_by_tool{{tool="{tool}"}} {count}')

lines.append("# TYPE dd_findings_by_cvss gauge")
for r in ("0-3", "4-6", "7-8", "9-10"):
    lines.append(f'dd_findings_by_cvss{{range="{r}"}} {cvss_ranges[r]}')

lines.append("# TYPE sdop_mttd_seconds gauge")
lines.append(f"sdop_mttd_seconds {avg_mttd:.3f}")

lines.append("# TYPE sdop_stage_duration_seconds gauge")
lines.append(f'sdop_stage_duration_seconds{{stage="defectdojo_ingest"}} {avg_mttd:.3f}')

lines.append("# TYPE sdop_findings_detected_total counter")
lines.append(f"sdop_findings_detected_total {total_findings}")

print("\n".join(lines))
PY
)
rm -f "$tmp_findings_file"

echo "[4/4] Pushing metrics to Pushgateway..."
instance="manual_sync"
payload_with_newline="${metrics_payload}"$'\n'
push_resp=$(curl -s -w "\n%{http_code}" --data-binary "$payload_with_newline" "$PUSHGATEWAY_URL/metrics/job/defectdojo_sync/instance/$instance")
push_code=$(echo "$push_resp" | tail -1)
if [[ "$push_code" != "200" && "$push_code" != "202" ]]; then
  echo "ERROR: Push failed with HTTP $push_code"
  echo "Response: $(echo "$push_resp" | head -n -1)"
  exit 1
fi

echo "Metrics pushed successfully (HTTP $push_code)."
echo ""
echo "Quick checks:"
echo "  curl -s $PUSHGATEWAY_URL/metrics | grep -E 'dd_|sdop_'"
echo "  curl -s 'http://localhost:9090/api/v1/query?query=sdop_mttd_seconds'"

