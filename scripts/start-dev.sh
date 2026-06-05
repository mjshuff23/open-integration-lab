#!/usr/bin/env bash

# start-dev.sh
#
# One-command startup for the full Open Integration Lab environment.
# Builds, deploys, migrates, and smoke-tests in a single invocation.
#
# Usage:
#   ./scripts/start-dev.sh              # build from source
#   ./scripts/start-dev.sh --no-build   # use existing images
#   ./scripts/start-dev.sh --tag v1.0   # explicit image tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPOSE_APP="$PROJECT_ROOT/infra/compose/compose.app.yml"
COMPOSE_CI="$PROJECT_ROOT/infra/compose/compose.ci.yml"
SMOKE_SCRIPT="$SCRIPT_DIR/smoke-test.sh"
ENV_FILE="$PROJECT_ROOT/.env"

[ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

NO_BUILD=false
TAG="${IMAGE_TAG:-latest}"

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) NO_BUILD=true; shift ;;
    --tag) TAG="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo "  Open Integration Lab — Dev Startup"
echo "  Tag:      $TAG"
echo "  Registry: ${REGISTRY:-localhost:5000}"
echo "  Build:    $($NO_BUILD && echo 'no' || echo 'yes')"
echo "=========================================="
echo ""

# ── 1. Start the full stack ──────────────────────────────────────────

echo "--- [1/5] Starting services ---"
docker compose -f "$COMPOSE_APP" -f "$COMPOSE_CI" up -d --remove-orphans db registry

echo "  Waiting for db to become healthy..."
for i in $(seq 1 30); do
  if docker compose -f "$COMPOSE_APP" ps db --format json 2>/dev/null | grep -q '"Health":.*healthy'; then
    echo "  db healthy after ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  ERROR: db not healthy after 30s"
    docker compose -f "$COMPOSE_APP" logs db
    exit 1
  fi
  sleep 1
done

COMPOSE_BOTH="-f $COMPOSE_APP -f $COMPOSE_CI"

if $NO_BUILD; then
  IMAGE_TAG="$TAG" docker compose $COMPOSE_BOTH up -d --remove-orphans backend frontend nginx registry registry-ui
else
  docker compose $COMPOSE_BOTH up -d --remove-orphans
fi

# Restart nginx so resolver refreshes upstream IPs
docker compose -f "$COMPOSE_APP" restart nginx

# ── 2. Run database migrations ───────────────────────────────────────

echo "--- [2/5] Running migrations ---"
if [ -f "$PROJECT_ROOT/apps/backend/prisma/schema.prisma" ]; then
  docker compose $COMPOSE_BOTH run --rm --remove-orphans \
    backend pnpm prisma:migrate:deploy
else
  echo "  No Prisma schema found — skipping"
fi

# ── 3. Build & push images ───────────────────────────────────────────

if ! $NO_BUILD; then
  echo "--- [3/5] Building images ---"
  docker build -t "${REGISTRY:-localhost:5000}/backend:$TAG" \
    -t "${REGISTRY:-localhost:5000}/backend:latest" \
    "$PROJECT_ROOT/apps/backend"
  docker build \
    --build-arg NEXT_PUBLIC_API_URL=/api \
    -t "${REGISTRY:-localhost:5000}/frontend:$TAG" \
    -t "${REGISTRY:-localhost:5000}/frontend:latest" \
    "$PROJECT_ROOT/apps/frontend"

  echo "  Pushing to registry..."
  docker push "${REGISTRY:-localhost:5000}/backend:$TAG"
  docker push "${REGISTRY:-localhost:5000}/backend:latest"
  docker push "${REGISTRY:-localhost:5000}/frontend:$TAG"
  docker push "${REGISTRY:-localhost:5000}/frontend:latest"

  echo "  Redeploying with fresh images..."
  IMAGE_TAG="$TAG" docker compose $COMPOSE_BOTH up -d --remove-orphans backend frontend nginx registry
else
  echo "--- [3/5] Skipping build (--no-build) ---"
fi

# ── 4. Wait for stack health ─────────────────────────────────────────

echo "--- [4/5] Health check ---"
BACKEND_URL="http://localhost:8080/api/health"
FRONTEND_URL="http://localhost:8080/"
for i in $(seq 1 30); do
  bk=false
  fr=false
  curl -sf "$BACKEND_URL" > /dev/null 2>&1 && bk=true
  curl -sf -o /dev/null "$FRONTEND_URL" > /dev/null 2>&1 && fr=true
  if $bk && $fr; then
    echo "  Stack healthy after ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  ERROR: Stack not healthy after 30s"
    echo "    Backend: $($bk && echo OK || echo FAIL)"
    echo "    Frontend: $($fr && echo OK || echo FAIL)"
    echo "  Logs: docker compose -f $COMPOSE_APP logs backend frontend"
    exit 1
  fi
  sleep 1
done

# ── 5. Smoke test ────────────────────────────────────────────────────

echo "--- [5/5] Smoke test ---"
"$SMOKE_SCRIPT"

echo ""
echo "=========================================="
echo "  Environment is live!"
echo "  App:        http://localhost:8080"
echo "  Registry:   http://localhost:5000/v2/_catalog"
echo "  Registry UI: http://localhost:8081"
echo "  Backend:    http://localhost:8080/api/health"
echo "=========================================="
