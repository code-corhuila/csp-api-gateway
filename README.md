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
nginx/templates/               settings rendered by envsubst at start (rate limit, CORS, service upstreams)
nginx/snippets/                headers every response carries, rate limit and preflight, credential filter
nginx/routes/                  one file per domain (auth.conf), plus _health.conf
tests/smoke.sh                 checks the gateway must pass
deploy/                        Dockerfile and compose.yml
```

## Configuration

| Variable | Meaning |
|---|---|
| `APP_GATEWAY_CORS_ORIGIN_REGEX` | Allowed browser origins, anchored by the gateway (`^...$`). Default: shell `4200` and remotes `4201`-`4205`. |
| `APP_GATEWAY_AUTH_UPSTREAM` | Base URL of `csp-auth-api` (scheme, host, port; no path). Default: `http://auth-api:8081`. |

See `.env.example`.

## Routes

| Path | Service | Authorization at the gateway |
|---|---|---|
| `/health` | the gateway itself | public |
| `/api/v1/auth/{register,login,refresh,forgot-password,reset-password,jwks,health,health/ready}` | `csp-auth-api` | public |
| `/api/v1/auth/{logout,me/*,users/{userId}/role}` | `csp-auth-api` | header required (401 without it) |
| `/api/v1/auth/internal/*` | `csp-auth-api` | never exposed (404): `csp-worker` calls the service directly |

Anything else answers 404. The gateway only checks that `Authorization` is present; each service
validates the token.

## Adding a domain

1. Add `APP_GATEWAY_<DOMAIN>_UPSTREAM` to `nginx/templates/20-upstreams.conf.template`, the
   Dockerfile, `deploy/compose.yml` and `.env.example`. Create `nginx/routes/<domain>.conf` with
   its `location` blocks and a **variable** in `proxy_pass` (`proxy_pass $<domain>_upstream;`) so
   the name is resolved per request. Start each proxied `location` with
   `snippets/route-common.conf` (rate limit, preflight) and add `snippets/require-auth.conf` to
   the protected ones.
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
