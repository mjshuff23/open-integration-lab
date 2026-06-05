# Cloud to Local Mapping

This doc maps the AWS learning architecture to open-source/containerized equivalents.

| AWS piece | Systems concept | Open Integration Lab equivalent |
|---|---|---|
| CloudFront | Public edge, HTTPS redirect, origin forwarding | Caddy, Nginx, Traefik, optional Varnish |
| ALB | Path routing and target groups | Nginx reverse proxy or Traefik routers |
| ECS Fargate | Long-running container scheduling | Docker Compose first, Nomad/k3s later |
| ECS task definitions | Container runtime contract | Compose services or OpenTofu Docker resources |
| ECR | Container image registry | Docker Distribution, Forgejo registry, Harbor |
| RDS Postgres | Managed database | PostgreSQL container with volumes and restore drills |
| Secrets Manager | Runtime secret delivery | SOPS + age, then OpenBao |
| CloudWatch | Logs, metrics, dashboards, alerts | OpenTelemetry Collector, Prometheus, Grafana/Perses, Loki/Vector |
| GitHub OIDC deploy role | Federated deploy identity | Local runner tokens, Forgejo/Woodpecker secrets |
| Terraform state | Infrastructure graph and state | OpenTofu local state, later encrypted/remote state |

## Important honesty boundary

This lab does not recreate a global CDN unless the project actually runs distributed edge nodes. The useful goal is to recreate the core systems lessons:

- ingress
- TLS termination
- path routing
- origin behavior
- service isolation
- image promotion
- runtime secrets
- telemetry
- stateful database operations
- backup and restore
- deploy rollback

## Local target contract

```text
Nginx
  -> /api and /api/* -> backend:4000
  -> /               -> frontend:3000
```

Do not strip `/api` unless the backend contract changes. The backend should remain compatible with a production-style single-origin setup.
