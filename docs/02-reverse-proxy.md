# Edge Reverse Proxy

## AWS concept mapping

```text
CloudFront              ->  Nginx (edge proxy on port 8080)
  + ALB                 ->    path-based routing
  + origin forwarding   ->    proxy_pass to upstream services
  + proxy headers       ->    proxy_set_header directives
```

In the AWS architecture, CloudFront handles edge termination (HTTPS, geographic distribution, origin shielding) and passes requests to an ALB which routes by path pattern to target groups. In this lab, **Nginx** is the single edge entrypoint that handles path routing and header forwarding.

## Why a proxy entrypoint matters

Without a reverse proxy, every service would need to expose ports directly:

```text
Browser -> backend:4000 (direct)
Browser -> frontend:3000 (direct)
```

This is operationally problematic:

- **CORS sprawl.** Every client needs to know every origin.
- **Port leakage.** Internal service topology becomes a public contract.
- **No central policy.** Auth, logging, rate limiting, and routing must be duplicated per service.
- **Brittle clients.** Frontend code hard-codes backend URLs and ports.

With a reverse proxy, the browser talks to one address:

```text
Browser -> proxy:8080/api/* -> backend:4000
Browser -> proxy:8080/*     -> frontend:3000
```

## Architecture

```text
┌──────────┐     ┌──────────────────────────────────────┐
│  Browser  │────▶│         Nginx (port 8080)            │
└──────────┘     │                                      │
                 │  /api      → 301 /api/               │
                 │  /api/*    → proxy_pass backend:4000  │
                 │  /*        → proxy_pass frontend:3000 │
                 └────┬─────────────────────┬────────────┘
                      │                     │
                      ▼                     ▼
              ┌──────────────┐     ┌──────────────┐
              │  backend:4000 │     │ frontend:3000 │
              │  /api/health  │     │  / (Next.js)  │
              └──────┬───────┘     └──────────────┘
                     │
                     ▼
              ┌──────────────┐
              │  db:5432     │
              │  PostgreSQL  │
              └──────────────┘
```

## Path routing rules

The following table shows exactly how Nginx matches paths. Order matters — Nginx evaluates locations in this priority:

1. Exact match (`= /path`)
2. Longest prefix match is selected and remembered (`/path/`)
3. Regex match (`~ pattern`) is then evaluated in declaration order
4. If a regex matches, that regex location is used; otherwise Nginx uses the remembered prefix match (`/` is just the fallback catch-all prefix)

### Current rules in `infra/nginx/conf.d/app.conf`

| Location | Match type | Upstream | Purpose |
|---|---|---|---|
| `= /api` | Exact | — (301) | Redirect bare `/api` to `/api/` |
| `/api/` | Prefix | `backend:4000` | All API requests |
| `/` | Prefix (catch-all) | `frontend:3000` | All frontend requests |

### Request flow examples

```
GET /                  → frontend:3000  → Next.js renders homepage
GET /login             → frontend:3000  → Next.js renders login
GET /api               → 301 → /api/   → redirect
GET /api/              → backend:4000  → NestJS router
GET /api/health        → backend:4000  → NestJS health controller
GET /api/auth/login    → backend:4000  → NestJS auth module
GET /static/image.png  → frontend:3000 → Next.js static files
```

## The `proxy_pass` slash foot-gun

A common mistake is accidentally stripping or duplicating the `/api` prefix through `proxy_pass` URI behavior.

### Rule

When `proxy_pass` includes a URI **path** (anything after the host), Nginx replaces the matched location prefix with that path. When `proxy_pass` has **no URI** (just `http://upstream;` or `http://$upstream;` with a variable), the original request URI is passed as-is.

### Examples of bad behavior

| `location` | `proxy_pass` | Incoming path | Sent to upstream | Result |
|---|---|---|---|---|
| `/api/` | `http://backend:4000/` | `/api/health` | `/health` | **BROKEN** — `/api` stripped |
| `/api/` | `http://backend:4000/api` | `/api/health` | `/api/health` | Works by accident, but trailing-slash mismatch |
| `/api/` | `http://backend:4000/api/` | `/api/health` | `/api/health` | Works |

### Our safe config

Our config uses a **variable** in `proxy_pass`, which avoids Nginx's URI replacement logic entirely:

```nginx
location /api/ {
    set $backend_upstream http://backend:4000;
    proxy_pass $backend_upstream;
}
```

Because `$backend_upstream` contains no URI path (just `http://backend:4000`), Nginx passes the **full original request URI** — including `/api/` — to the backend. This is the safest pattern for prefix-based routing.

> **Important:** If the backend drops the global `/api` prefix in the future, update both the backend route prefix and this doc. The proxy should always match the backend contract.

## Proxy headers

Nginx forwards these headers to upstream services:

| Header | Value | Purpose |
|---|---|---|
| `Host` | `$host` | Preserve original hostname |
| `X-Real-IP` | `$remote_addr` | Client IP address |
| `X-Forwarded-For` | `$proxy_add_x_forwarded_for` | Client IP chain |
| `X-Forwarded-Proto` | `$scheme` | Original protocol (http/https) |

These headers are required for the backend to know the real client address and protocol, especially when running behind a proxy.

## Verification

Start the full stack:

```bash
./scripts/start-dev.sh
```

### Test proxy routing

```bash
# Frontend through proxy
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# Expected: 200

# Backend through proxy
curl http://localhost:8080/api/health
# Expected: {"status":"ok","timestamp":"..."}

# Bare /api redirects
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api
# Expected: 301 (redirecting to /api/)
```

### Run the smoke test suite

```bash
./scripts/smoke-test.sh
```

## Debugging: frontend vs backend vs proxy failure

When a request fails, isolate the layer:

### 1. Is the proxy reachable?

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
```

If this returns **no response** or a connection refused error, the proxy (Nginx) is down or the port is wrong. Check:

```bash
docker compose -f infra/compose/compose.app.yml ps nginx
docker compose -f infra/compose/compose.app.yml logs nginx
```

### 2. Is the backend reachable directly?

```bash
curl http://localhost:4000/api/health
```

- If this works but `http://localhost:8080/api/health` fails: the **proxy routing** is broken.
- If this fails: the **backend** or its dependency (database) is broken.

### 3. Is the frontend reachable directly?

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/
```

- If this works but `http://localhost:8080/` fails: the **proxy routing** is broken.
- If this fails: the **frontend** is broken.

### 4. Check proxy logs

```bash
docker compose -f infra/compose/compose.app.yml logs nginx
```

Nginx access logs (if enabled) show every request with upstream status codes, which makes it easy to distinguish proxy failures (5xx) from client errors (4xx) from success (2xx).

### Common HTTP statuses at the proxy

| Status | Meaning | Likely cause |
|---|---|---|
| 200 | OK | Request routed and served successfully |
| 301 | Redirect | Bare `/api` redirected to `/api/` |
| 502 | Bad Gateway | Upstream service is down or unreachable |
| 503 | Service Unavailable | Upstream is overloaded or refusing connection |
| 504 | Gateway Timeout | Upstream didn't respond in time |

## Failure drill

This drill verifies that proxy failures are distinguishable from backend failures.

### Setup

Ensure the stack is running:

```bash
./scripts/start-dev.sh --no-build
```

### Step 1: Confirm backend is healthy through proxy

```bash
curl http://localhost:8080/api/health
# Expected: {"status":"ok","timestamp":"..."}
```

### Step 2: Stop the backend

```bash
docker compose -f infra/compose/compose.app.yml stop backend
```

### Step 3: Observe proxy failure

```bash
curl -i http://localhost:8080/api/health
```

**Expected:** Nginx returns `502 Bad Gateway` with an nginx-specific error page. The proxy is working — it correctly identifies that the upstream is unreachable. This is different from a backend crash (which would return no response at all if accessed directly).

The proxy logs will show:

```
[error] ... upstream prematurely closed connection ... while reading response header from upstream, client: ..., server: , request: "GET /api/health HTTP/1.1", upstream: "http://172.x.x.x:4000/api/health"
```

### Step 4: Verify frontend is still served

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# Expected: 200
```

The frontend should continue working because its upstream (`frontend:3000`) is independent of the backend.

### Step 5: Restore and verify

```bash
docker compose -f infra/compose/compose.app.yml start backend
./scripts/smoke-test.sh
```
