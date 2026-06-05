#!/usr/bin/env bash

# smoke-test.sh
#
# Verifies the stack is healthy by checking through the edge proxy.
#
# Tests:
#   1. Frontend responds at /
#   2. Backend responds at /api/health
#
# Usage:
#   ./scripts/smoke-test.sh

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
FAILED=0

echo "Smoke testing stack at $BASE_URL"
echo ""

# Test 1: Frontend
echo "--- Test 1: Frontend (GET /) ---"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/")
if [ "$STATUS" = "200" ]; then
  echo "  PASS: Frontend returned 200"
else
  echo "  FAIL: Frontend returned $STATUS (expected 200)"
  FAILED=1
fi

# Test 2: Backend health
echo "--- Test 2: Backend health (GET /api/health) ---"
HEALTH=$(curl -sf "$BASE_URL/api/health" 2>/dev/null || echo "")
if echo "$HEALTH" | grep -q '"status":"ok"'; then
  echo "  PASS: Backend returned healthy"
else
  echo "  FAIL: Backend health check failed (got: $HEALTH)"
  FAILED=1
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All smoke tests passed."
else
  echo "Some smoke tests failed."
  exit 1
fi
