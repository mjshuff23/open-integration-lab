# Architecture Overview

Open Integration Lab is a local glass-box version of a common AWS web-app deployment pattern.

## Target flow

```text
Browser
  -> local edge proxy
      /api* -> backend service
      /*    -> frontend service

backend service
  -> PostgreSQL
  -> runtime secrets
  -> logs, metrics, and traces
```

## Why this architecture exists

The original cloud architecture wraps a lot of systems work in managed services:

- CloudFront handles edge behavior.
- ALB handles routing and target groups.
- ECS Fargate handles container scheduling.
- RDS handles database durability and recovery.
- ECR handles image registry behavior.
- Secrets Manager handles secret storage and delivery.
- CloudWatch handles telemetry collection.
- GitHub Actions plus IAM/OIDC handles deploy identity.

This lab makes those same concepts visible with local and open-source primitives.

## Baseline components

| Layer | Baseline choice | Purpose |
|---|---|---|
| Runtime | Docker Compose | Run the first production-ish local stack |
| Edge | Nginx | Learn explicit reverse proxy rules |
| Database | PostgreSQL container | Learn database lifecycle, volumes, backup, and restore |
| IaC | OpenTofu | Manage durable local infra primitives |
| Registry | Docker Distribution first, Harbor later | Learn image push, pull, and promotion |
| Secrets | SOPS + age first, OpenBao later | Learn encrypted config and secret-server patterns |
| Metrics | Prometheus | Learn pull-based service metrics |
| Telemetry | OpenTelemetry Collector | Learn vendor-neutral telemetry routing |
| CI/CD | Woodpecker or Forgejo Actions | Learn self-hosted deploy automation |
| Private access | WireGuard or Headscale | Learn private networking |
| Scheduler | Nomad or k3s later | Learn what ECS Fargate abstracts |

## First acceptance target

```bash
docker compose config
docker compose up --build
curl http://localhost:8080/
curl http://localhost:8080/api/health
```

## Design rule

Do not jump to Kubernetes or a fancy platform until the basic pipe is visible:

```text
request -> proxy -> service -> database -> response
```

That pipe is the spine. Everything else is ribs and dashboard glitter.
