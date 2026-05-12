#!/bin/bash
# Debug script to check DefectDojo → Prometheus → Grafana data flow

PUSHGATEWAY_URL="${1:-http://localhost:9091}"
PROMETHEUS_URL="${2:-http://localhost:9090}"
GRAFANA_URL="${3:-http://localhost:3000}"

echo "================================================================"
echo "🔍 DefectDojo → Grafana Data Flow Debugging"
echo "================================================================"
echo ""

# Step 1: Check Pushgateway metrics
echo "📤 [1/3] Checking Pushgateway metrics..."
echo "URL: $PUSHGATEWAY_URL/metrics"
echo ""

PG_METRICS=$(curl -s "$PUSHGATEWAY_URL/metrics" 2>&1)

if [[ -z "$PG_METRICS" ]]; then
  echo "❌ Cannot connect to Pushgateway at $PUSHGATEWAY_URL"
  exit 1
fi

DEFECTDOJO_METRICS=$(echo "$PG_METRICS" | grep "^defectdojo_" | grep -v "^#")

if [[ -z "$DEFECTDOJO_METRICS" ]]; then
  echo "❌ NO METRICS found in Pushgateway!"
  echo ""
  echo "📌 All metrics in Pushgateway:"
  echo "$PG_METRICS" | grep "^[a-zA-Z]" | head -20
  echo ""
  echo "💡 Troubleshooting:"
  echo "   1. Run the sync script again:"
  echo "      ./scripts/defectdojo-to-grafana.sh --url http://localhost:8000 --api-key YOUR_KEY"
  echo "   2. Check Pushgateway is running: docker ps | grep pushgateway"
  echo "   3. Check script output for errors"
else
  echo "✅ Found DefectDojo metrics in Pushgateway:"
  echo "$DEFECTDOJO_METRICS"
  echo ""
  
  # Step 2: Check if Prometheus scraped Pushgateway
  echo "📊 [2/3] Checking if Prometheus scraped metrics..."
  echo "URL: $PROMETHEUS_URL/api/v1/query"
  echo ""
  
  for metric in "defectdojo_findings_critical" "defectdojo_findings_high" "defectdojo_findings_medium" "defectdojo_findings_low"; do
    PROM_QUERY=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric" 2>&1)
    PROM_RESULT=$(echo "$PROM_QUERY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('result',[]))" 2>/dev/null || echo "[]")
    
    if [[ "$PROM_RESULT" == "[]" ]]; then
      echo "   ⚠️  $metric - NOT in Prometheus yet (may be waiting for scrape interval)"
    else
      echo "   ✅ $metric - Found in Prometheus"
      echo "      $PROM_RESULT"
    fi
  done
fi

echo ""
echo "================================================================"
echo "🔗 Quick Fix Steps:"
echo "================================================================"
echo ""
echo "If Pushgateway has metrics but Prometheus doesn't:"
echo "  1. Check Prometheus config includes Pushgateway:"
echo "     docker exec prometheus cat /etc/prometheus/prometheus.yml | grep pushgateway"
echo ""
echo "  2. Restart Prometheus to reload config:"
echo "     docker restart prometheus"
echo ""
echo "  3. Force a scrape (wait 10-60 seconds for default interval)"
echo ""
echo "If Prometheus has metrics but Grafana doesn't:"
echo "  1. Verify Grafana data source: http://localhost:3000 → Settings → Data Sources"
echo "  2. Check Prometheus is reachable from Grafana"
echo "  3. Edit dashboard panels to use correct metric names"
echo ""
echo "Useful commands:"
echo "  # Check Pushgateway"
echo "  curl http://localhost:9091/metrics | grep defectdojo"
echo ""
echo "  # Check Prometheus targets"
echo "  curl http://localhost:9090/api/v1/targets | python3 -m json.tool"
echo ""
echo "  # Query metric directly in Prometheus"
echo "  curl 'http://localhost:9090/api/v1/query?query=defectdojo_findings_critical'"
echo ""
echo "================================================================"
