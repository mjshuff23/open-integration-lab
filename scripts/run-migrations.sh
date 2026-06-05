#!/usr/bin/env bash

# run-migrations.sh
#
# Runs Prisma migrations against the running database.
#
# Replaces: AWS ECS one-off Fargate task running prisma:migrate:deploy
#
# System concept:
#   Database migrations are a separate lifecycle from application deploys.
#   They run *before* the new service starts so the schema is ready
#   for both old and new code during a rolling update.
#
# Usage:
#   ./scripts/run-migrations.sh
#
# This depends on:
#   - The db service running (via compose.app.yml)
#   - DATABASE_URL configured in compose.app.yml's backend service

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_APP="$PROJECT_ROOT/infra/compose/compose.app.yml"

if [ ! -f "$COMPOSE_APP" ]; then
  echo "ERROR: compose.app.yml not found at $COMPOSE_APP"
  exit 1
fi

echo "Running Prisma migrations..."
echo "Compose file: $COMPOSE_APP"

docker compose -f "$COMPOSE_APP" run --rm \
  backend pnpm prisma:migrate:deploy

echo "Migrations complete."
