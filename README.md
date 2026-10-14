# csp-api-gateway

> Single entry point of the platform: routing, rate limiting and the cheap credential filter

Part of the **Cinesync Platform** distributed system — team `cinesync-platform`, Group 1.
Governance and documentation live in [`csp-docs`](https://github.com/code-corhuila/csp-docs).

## Purpose

Declarative NGINX gateway (Annex F of the norm): configuration, not code. It routes
`/api/v1/<domain>/...` to the owning service, rejects a protected request that carries no
`Authorization` header, applies a stateless per-IP rate limit and CORS, reuses or creates
`X-Correlation-Id`, and answers its own errors with the shared error envelope. It does **not**
validate tokens (each service does, norm 5.6.2), keeps no state and has no business logic.

## Stack

| Item | Value |
|---|---|
| Proxy | NGINX `1.27-alpine` |
| Port | `8000` (only service published to the host) |
| Compose service | `api-gateway` (`name: csp-api-gateway`, external network `platform`) |

## Structure

```
nginx/nginx.conf               global settings, JSON access log with correlationId
nginx/conf.d/                  per-request DNS resolver, server with the gateway's own errors
nginx/templates/               security settings rendered by envsubst at start (rate limit, CORS)
nginx/snippets/headers.conf    headers every response carries
nginx/routes/                  one file per domain, plus _health.conf
tests/smoke.sh                 checks the gateway must pass
deploy/                        Dockerfile and compose.yml
```

## Configuration

| Variable | Meaning |
|---|---|
| `APP_GATEWAY_CORS_ORIGIN_REGEX` | Allowed browser origins, anchored by the gateway (`^...$`). Default: shell `4200` and remotes `4201`-`4205`. |

See `.env.example`.

## Adding a domain

1. Create `nginx/routes/<domain>.conf` with its `location` blocks and a **variable** in
   `proxy_pass` (`set $x http://host:port; proxy_pass $x;`) so the name is resolved per request.
2. Include `snippets/headers.conf` in any `location` that adds its own headers.
3. Extend `tests/smoke.sh`; the CI runs it on every Pull Request.

## Build, test, run

```bash
docker build -f deploy/Dockerfile -t gateway .
docker run --rm gateway nginx -t
docker run -d --name gateway -p 8000:8000 gateway
sh tests/smoke.sh http://localhost:8000
```

## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `csp-docs`.
