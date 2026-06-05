# Deploy Pipeline

## AWS concept mapping

```text
GitHub Actions deploy workflow
  -> Scripted local deploy pipeline
  -> optional self-hosted runner later
  -> optional Forgejo/Woodpecker CI later

ECS service update
  -> pull new image tag + docker compose up -d

One-off Fargate migration task
  -> docker compose run --rm backend prisma:migrate:deploy

ECR image push
  -> docker push localhost:5000/<service>:<tag>

Task definition revision
  -> IMAGE_TAG env var in compose.app.yml

Service rollback to previous task revision
  -> rollback-deploy.sh <previous-tag>
```

## What the AWS deploy workflow does

The original `aws-integration-repo` GitHub Actions workflow (`deploy.yml`) runs this sequence:

1. Build backend image, tag with `${{ github.sha }}`, push to ECR
2. Build frontend image with `NEXT_PUBLIC_API_URL=/api`, push to ECR
3. Register a new ECS task definition revision with the updated image URI
4. Run Prisma migrations as a one-off Fargate task (command override)
5. Update the backend ECS service with `--force-new-deployment`
6. Update the frontend ECS service

Key properties of the AWS pipeline:

| Property | Mechanism |
|---|---|
| Auth | GitHub OIDC -> IAM role -> ECR + ECS |
| Image identity | Immutable `github.sha` tag |
| Schema safety | Migrations run *before* service update |
| Rollback | Re-register task def with previous image tag |
| State | ECS service knows its task definition revision |

## What the local pipeline preserves

The local `deploy-local.sh` preserves every step, replacing AWS calls with Docker CLI:

| AWS step | Local equivalent |
|---|---|
| `docker build` + push to ECR | `docker build` + push to `localhost:5000` |
| Register task def revision | Not needed — compose reads `IMAGE_TAG` at runtime |
| One-off Fargate migration | `docker compose run --rm backend prisma:migrate:deploy` |
| `ecs update-service` | `IMAGE_TAG=<tag> docker compose up -d` |
| `ecs wait services-stable` | Health check loop against `/api/health` |
| Smoke via CloudWatch | `curl` through the edge proxy |
| Rollback via task def revision | `rollback-deploy.sh <tag>` |

## Pipeline diagram

```text
deploy-local.sh
│
├── 1. lint & test
│     (pnpm lint + pnpm test in each app)
│
├── 2. docker build
│     backend:$TAG + frontend:$TAG
│     (also tagged :latest)
│
├── 3. docker push
│     -> localhost:5000/backend:$TAG
│     -> localhost:5000/frontend:$TAG
│
├── 4. prisma:migrate:deploy
│     (docker compose run --rm backend)
│     Schema changes applied BEFORE new code rolls out
│
├── 5. IMAGE_TAG=$TAG docker compose up -d
│     Recreates backend and frontend containers
│
├── 6. health check
│     curl http://localhost:8080/api/health (up to 30s)
│
├── 7. smoke test
│     ./scripts/smoke-test.sh
│
└── 8. persist state
      .deploy.env written with CURRENT_TAG + PREVIOUS_TAG
```

## Why migrations run before service rollout

This is the most critical ordering constraint in the pipeline and mirrors the AWS deploy exactly.

```text
Timeline:     t0         t1         t2
Schema:       old  ─────►  new
Backend v1:   run  ─────►  drain
Backend v2:                  start ──►  run
                          (sees new schema)
```

If migrations ran *after* the new service started:

```text
Timeline:     t0         t1         t2
Schema:       old                  ──►  new
Backend v2:   start ──►  crash ──►  run
                     (wrong schema)
```

The new container would crash-loop on startup because the schema is incompatible. By running migrations first, the database is ready for both the old service (still running during the transition) and the new service (starting after health check).

In the AWS pipeline this is a one-off Fargate task. In the local pipeline it is `docker compose run --rm`.

## Why immutable image tags help rollback

### The problem with `:latest`

```bash
docker build -t backend:latest .
docker compose up -d
# ... oh no, the deploy broke
# Which tag was running before?
```

`:latest` is a moving pointer. After a failed deploy you cannot tell what was running before unless you manually tracked it. This is the same reason ECS task definitions are immutable revisions — you always know what you are rolling back to.

### The solution: git SHA tags

```bash
TAG=$(git rev-parse --short HEAD)
docker build -t backend:$TAG .
docker push backend:$TAG
# Deploy fails
docker pull backend:$PREVIOUS_TAG
# Exactly the same bits as before
```

Every commit produces a unique, immutable image tag. The deploy pipeline records `CURRENT_TAG` and `PREVIOUS_TAG` in `.deploy.env` so rollback always has a target.

```text
.deploy.env
├── CURRENT_TAG=a1b2c3d    ← what is running now
└── PREVIOUS_TAG=4e5f6g7   ← what was running before
```

## Files

| File | Purpose |
|---|---|
| `infra/compose/compose.ci.yml` | CI overlay: local registry + web UI |
| `scripts/deploy-local.sh` | Full deploy pipeline |
| `scripts/run-migrations.sh` | Standalone migration runner |
| `scripts/rollback-deploy.sh` | Rollback by image tag |
| `.deploy.env` | Runtime deploy state (gitignored) |
| `.deploy.env.example` | Template for deploy state |

## Usage

### Prerequisites

Before the deploy pipeline works, the foundation must be in place:

- `apps/backend/` with Dockerfile and package.json
- `apps/frontend/` with Dockerfile and package.json
- `infra/compose/compose.app.yml` with services: db, backend, frontend, nginx
- `scripts/smoke-test.sh` for post-deploy verification
- Docker and docker compose plugin installed

### Start the full stack (foundation + CI)

```bash
docker compose \
  -f infra/compose/compose.app.yml \
  -f infra/compose/compose.ci.yml \
  up -d
```

This starts the app stack plus the local registry on port `5000` and registry UI on port `8081`.

### Run the deploy pipeline

```bash
./scripts/deploy-local.sh
```

Output:

```text
==========================================
  Deploy pipeline
  Tag:        a1b2c3d
  Registry:   localhost:5000
  Previous:   4e5f6g7
==========================================

--- [1/7] Lint & test ---
...
--- [2/7] Build images ---
...
--- [3/7] Push images to registry ---
...
--- [4/7] Run migrations ---
...
--- [5/7] Redeploy services ---
...
--- [6/7] Health check ---
Backend healthy after 3s
--- [7/7] Smoke test ---
...
==========================================
  Deploy complete: a1b2c3d
==========================================
```

### Run migrations independently

```bash
./scripts/run-migrations.sh
```

Useful when you need to apply schema changes without a full deploy (e.g., after a rollback).

### Roll back a deploy

```bash
# Roll back to the previous tag
./scripts/rollback-deploy.sh

# Roll back to a specific tag
./scripts/rollback-deploy.sh a1b2c3d
```

## CI graduation path

The deploy pipeline starts as scripts and can graduate through three stages:

### Stage 1: Local scripts (now)

```text
./scripts/deploy-local.sh
```

Advantages: Zero infrastructure, works on any machine, fully transparent.

Limitations: No automation, no webhook triggers, no PR gating, no shared state.

### Stage 2: Self-hosted GitHub Actions runner

```text
GitHub repo → self-hosted runner → calls deploy-local.sh
```

Add a self-hosted runner to the Docker Compose stack. The runner polls GitHub for workflow jobs and executes them locally. The workflow file mirrors the AWS version but calls `./scripts/deploy-local.sh` instead of `aws ecs update-service`.

To add: containerize the runner image (`myoung34/github-runner`), register it in the repo, and create a `.github/workflows/deploy-local.yml`.

Relevant Docker image: `myoung34/github-runner:latest`

### Stage 3: Forgejo + Woodpecker

```text
Forgejo (self-hosted Git)
  → Woodpecker CI (self-hosted runner)
    → runs deploy-local.sh
    → pushes to local registry
    → deploys via compose
```

Full self-hosted alternative to GitHub + GitHub Actions. Forgejo replaces the Git host, Woodpecker replaces the CI executor. Both run as Docker Compose services.

This is the end state: no external SaaS dependency for the deploy path at all.

### When to graduate

| Scenario | Stage |
|---|---|
| Learning the pipeline mechanics | 1 |
| Team wants PR gating without GitHub-hosted runners | 2 |
| Team wants zero external SaaS dependency | 3 |
| Need to demonstrate the full ECS→Nomad/k3s migration | 3+ |

## Failure modes

### Registry unreachable

```text
ERROR: Registry not reachable at localhost:5000
```

**Cause:** The local registry container is not running. Start it with `compose.ci.yml`.

**Fix:**
```bash
docker compose -f infra/compose/compose.app.yml -f infra/compose/compose.ci.yml up -d registry
```

### Migration fails

```text
Migration task failed — the new schema is incompatible with data
```

**Cause:** Prisma migration has an error (e.g., NOT NULL column on table with data).

**Fix:** Roll back the migration, fix the migration file, re-run:
```bash
./scripts/rollback-deploy.sh  # restore previous schema-compatible code
./scripts/run-migrations.sh   # apply the fixed migration
./scripts/deploy-local.sh     # re-deploy
```

### Unhealthy deploy

```text
ERROR: Backend failed to become healthy after 30s
```

**Cause:** New container crashes on startup (bad code, wrong env, DB connection failure).

**Fix:**
```bash
docker compose -f infra/compose/compose.app.yml logs backend
./scripts/rollback-deploy.sh
```

### Stale rollback tag

```text
ERROR: Tag a1b2c3d not found for backend in registry
```

**Cause:** The registry was pruned or the tag never existed.

**Fix:** Rebuild from the git ref:
```bash
git checkout a1b2c3d
./scripts/deploy-local.sh a1b2c3d
git checkout main
```

## Verification

```bash
# Deploy with current git SHA
./scripts/deploy-local.sh

# Smoke test passes
./scripts/smoke-test.sh

# Roll back to previous tag
./scripts/rollback-deploy.sh

# Smoke test still passes
./scripts/smoke-test.sh

# Deploy with explicit tag
./scripts/deploy-local.sh test-rollback

# Roll back to explicit tag
./scripts/rollback-deploy.sh <original-sha>

# Run migrations independently
./scripts/run-migrations.sh

# Check registry inventory
curl http://localhost:5000/v2/_catalog
curl http://localhost:5000/v2/backend/tags/list
curl http://localhost:5000/v2/frontend/tags/list
```
