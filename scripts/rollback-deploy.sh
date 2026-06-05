#!/usr/bin/env bash

# rollback-deploy.sh
#
# Rolls back backend and frontend services to a previous image tag.
#
# Replaces: Reverting an ECS service to a previous task definition revision
#
# System concept:
#   Immutable image tags (git SHA) enable precise rollback.
#   Because every deploy creates a unique tag, you can always
#   go back to exactly what was running before.
#
# Usage:
#   ./scripts/rollback-deploy.sh              # roll back to PREVIOUS_TAG
#   ./scripts/rollback-deploy.sh <tag>         # roll back to a specific tag
#
# State:
#   Reads .deploy.env for current/previous tags.
#   Rewrites .deploy.env after rollback so the swapped tags are persisted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEPLOY_STATE="$PROJECT_ROOT/.deploy.env"
COMPOSE_APP="$PROJECT_ROOT/infra/compose/compose.app.yml"
REGISTRY="${REGISTRY:-localhost:5000}"
SMOKE_SCRIPT="$SCRIPT_DIR/smoke-test.sh"

# ── Prerequisite checks ──────────────────────────────────────────────

if [ ! -f "$DEPLOY_STATE" ]; then
  echo "ERROR: .deploy.env not found — no deploy state to roll back from"
  exit 1
fi

source "$DEPLOY_STATE"

if [ ! -f "$COMPOSE_APP" ]; then
  echo "ERROR: compose.app.yml not found at $COMPOSE_APP"
  exit 1
fi

# ── Determine rollback tag ───────────────────────────────────────────

ROLLBACK_TAG=""
if [ $# -ge 1 ]; then
  ROLLBACK_TAG="$1"
elif [ -n "${PREVIOUS_TAG:-}" ]; then
  ROLLBACK_TAG="$PREVIOUS_TAG"
fi

if [ -z "$ROLLBACK_TAG" ]; then
  echo "ERROR: No rollback tag specified and no PREVIOUS_TAG in .deploy.env"
  echo "Usage: $0 [<tag>]"
  exit 1
fi

if [ "$ROLLBACK_TAG" = "${CURRENT_TAG:-}" ]; then
  echo "Tag $ROLLBACK_TAG is already the current deploy — nothing to do"
  exit 0
fi

# ── Verify tag exists in registry ───────────────────────────────────

echo "Verifying tag $ROLLBACK_TAG in registry..."
if ! curl -sf "http://${REGISTRY}/v2/backend/manifests/${ROLLBACK_TAG}" > /dev/null 2>&1; then
  echo "ERROR: Tag $ROLLBACK_TAG not found for backend in registry"
  echo "Available tags:"
  curl -s "http://${REGISTRY}/v2/backend/tags/list" 2>/dev/null || echo "(registry unreachable)"
  exit 1
fi

echo "=========================================="
echo "  Rollback deploy"
echo "  Target tag: $ROLLBACK_TAG"
echo "  Current:    ${CURRENT_TAG:-none}"
echo "=========================================="
echo ""

# ── Pull the rollback images ───────────────────────────────────────

echo "--- Pull images ---"
docker pull "$REGISTRY/backend:$ROLLBACK_TAG"
docker pull "$REGISTRY/frontend:$ROLLBACK_TAG"

# ── Redeploy with rollback tag ─────────────────────────────────────

echo "--- Redeploy services ---"
IMAGE_TAG="$ROLLBACK_TAG" docker compose -f "$COMPOSE_APP" up -d backend frontend

# ── Wait for health ────────────────────────────────────────────────

echo "--- Health check ---"
HEALTH_URL="http://localhost:8080/api/health"
for i in $(seq 1 30); do
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Backend healthy after ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Backend failed to become healthy after 30s"
    echo "Check logs: docker compose -f $COMPOSE_APP logs backend"
    exit 1
  fi
  sleep 1
done

# ── Smoke test ─────────────────────────────────────────────────────

echo "--- Smoke test ---"
"$SMOKE_SCRIPT"

# ── Persist updated state ──────────────────────────────────────────

echo "--- Persist deploy state ---"
NEW_PREVIOUS="${CURRENT_TAG:-}"
cat > "$DEPLOY_STATE" <<EOF
REGISTRY=$REGISTRY
CURRENT_TAG=$ROLLBACK_TAG
PREVIOUS_TAG=$NEW_PREVIOUS
EOF

echo ""
echo "=========================================="
echo "  Rollback complete: $ROLLBACK_TAG"
echo "=========================================="
