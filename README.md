# Open Integration Lab

Open Integration Lab is a local-first, open-source/containerized learning project that recreates the important systems lessons from `aws-integration-repo` without treating the cloud as magic.

The point is not to fake AWS. The point is to make the parts AWS hides visible:

```text
Browser
  -> edge proxy
  -> frontend container
  -> backend container
  -> PostgreSQL container
  -> local registry
  -> secrets workflow
  -> observability stack
  -> backup/restore drills
  -> optional scheduler branch
```

## Core contract

The lab preserves the production-style contract from the AWS version:

- Frontend service
- Backend service
- PostgreSQL database
- `/api` path routing through one public origin
- Runtime secrets
- Container image deployment
- Database migrations before deploy
- Observability
- Backup and restore drills
- Reproducible infrastructure definitions

## Default learning path

1. Compose parity stack
2. Nginx edge routing
3. OpenTofu-managed local infra primitives
4. Local OCI registry and image promotion
5. SOPS/OpenBao secrets workflow
6. Prometheus/OpenTelemetry observability
7. Self-hosted CI/CD
8. Backup/restore and outage drills
9. WireGuard/Headscale private access
10. Nomad/k3s advanced scheduler branch

## Documentation

Start here:

- [`docs/README.md`](docs/README.md)
- [`docs/00-architecture.md`](docs/00-architecture.md)
- [`docs/01-cloud-to-local-mapping.md`](docs/01-cloud-to-local-mapping.md)
- [`docs/linear/README.md`](docs/linear/README.md)

## First target architecture

```text
localhost:8080
  -> nginx
      /api* -> backend:4000
      /*    -> frontend:3000

backend
  -> postgres:5432
```

## First commands

```bash
./scripts/lab.sh up
./scripts/smoke-test.sh
./scripts/lab.sh logs
./scripts/lab.sh down
```

## Non-goals

- No paid SaaS dependencies for the baseline lab.
- No cloud provider resources in the core path.
- No Kubernetes-first abstraction fog.
- No exposed PostgreSQL ports in production-like flows.
- No plaintext production-like secrets committed to the repo.

This repo should be the glass-box version of the AWS architecture: every pipe visible, every daemon inspectable, every outage teachable.
