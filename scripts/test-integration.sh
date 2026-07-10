#!/bin/bash
# Integration test — hits real Hermes API
# Usage: API_URL=https://storozhev.me/hermes-api API_KEY=xxx make test-integration

API_URL="${API_URL:-https://storozhev.me/hermes-api}"
API_KEY="${API_KEY:-}"
PASS=0
FAIL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  ✅ $desc"
        ((PASS++))
    else
        echo "  ❌ $desc"
        echo "     Expected: $expected"
        echo "     Got:      $actual"
        ((FAIL++))
    fi
}

echo "🔍 Testing Hermes API at $API_URL"
echo ""

# 1. Health check
echo "--- Health ---"
HEALTH=$(curl -s "$API_URL/v1/health" -H "Authorization: Bearer $API_KEY" -w "\nHTTP:%{http_code}")
assert "Health returns 200" "HTTP:200" "$HEALTH"
assert "Status is ok" '"status":"ok"' "$HEALTH"

# 2. Create run
echo "--- Create Run ---"
RUN=$(curl -s -X POST "$API_URL/v1/runs" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"input":"Reply with exactly: OK"}')
assert "Create run returns run_id" '"run_id"' "$RUN"

RUN_ID=$(echo "$RUN" | python3 -c "import sys,json; print(json.load(sys.stdin)['run_id'])" 2>/dev/null)
echo "     Run ID: $RUN_ID"

# 3. Stream events
echo "--- SSE Stream ---"
SSE=$(curl -s -N "$API_URL/v1/runs/$RUN_ID/events" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Accept: text/event-stream" \
    --max-time 30 2>/dev/null)
assert "SSE contains message.delta" '"event": "message.delta"' "$SSE"
assert "SSE contains run.completed" '"event": "run.completed"' "$SSE"
assert "SSE has output field" '"output"' "$SSE"

# 4. Capabilities
echo "--- Capabilities ---"
CAPS=$(curl -s "$API_URL/v1/capabilities" -H "Authorization: Bearer $API_KEY")
assert "Capabilities has features" '"features"' "$CAPS"
assert "SSE streaming supported" '"run_events_sse": true' "$CAPS"

echo ""
echo "══════════════════════════"
echo "  Passed: $PASS  Failed: $FAIL"
echo "══════════════════════════"
exit $FAIL
