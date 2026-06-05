# Reverse Proxy

## Goal

Replace the CloudFront plus ALB routing lesson with local edge routing that is easy to inspect.

## Default path

Use Nginx first because it exposes the mechanics directly:

- server blocks
- location blocks
- upstream services
- forwarded headers
- path matching

## Target routing

```text
localhost:8080
  -> nginx
      /api     -> backend:4000
      /api/*   -> backend:4000
      /*       -> frontend:3000
```

## Header behavior

The proxy should preserve original request context for the backend:

- Host
- X-Real-IP
- X-Forwarded-For
- X-Forwarded-Proto

## Files

Expected first implementation files:

```text
infra/compose/compose.app.yml
infra/nginx/nginx.conf
infra/nginx/conf.d/app.conf
scripts/lab.sh
scripts/smoke-test.sh
```

## Acceptance criteria

```bash
./scripts/lab.sh up
curl http://localhost:8080/
curl http://localhost:8080/api/health
curl http://localhost:8080/api/docs
```

## Agent guardrails

- Do not expose backend and frontend directly as the primary browser entrypoint.
- Do not strip `/api` unless a ticket explicitly changes the backend contract.
- Do not add Traefik or Caddy before Nginx parity works.
- Do not expose Postgres through the edge proxy.
