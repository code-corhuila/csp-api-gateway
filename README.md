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
nginx/entrypoint/              start-time check: https:// Catalog upstream and CA file (fail closed)
nginx/snippets/                headers every response carries, preflight, rate limit, credential filter
nginx/routes/                  one file per domain (auth.conf, booking.conf, catalog.conf, concessions.conf, ticketing.conf, workflow.conf), plus _health.conf
tests/smoke.sh                 checks the gateway must pass
deploy/                        Dockerfile and compose.yml
```

## Configuration

| Variable | Meaning |
|---|---|
| `APP_GATEWAY_CORS_ORIGIN_REGEX` | Allowed browser origins, anchored by the gateway (`^...$`). Default: shell `4200` and remotes `4201`-`4205`. |
| `APP_GATEWAY_AUTH_UPSTREAM` | Base URL of `csp-auth-api` (scheme, host, port; no path). Default: `http://auth-api:8081`. |
| `APP_GATEWAY_CONCESSIONS_UPSTREAM` | Base URL of `csp-concessions-api` (scheme, host, port; no path). Default: `http://concessions-api:8085`. |
| `APP_GATEWAY_CATALOG_UPSTREAM` | Base URL of `csp-catalog-api` (scheme, host, port; no path). Must be `https://` (default: `https://catalog-api:8082`); the gateway does not start otherwise. |
| `CATALOG_TLS_CA_FILE` | CA certificate (public) that verifies Catalog. Always `/run/tls/ca.crt` in the container; the compose file mounts it read-only from the host file `CATALOG_TLS_CA_HOST_FILE` (defined by the platform repository `csp-infra-postgres`; compose refuses to start without it). |
| `APP_GATEWAY_BOOKING_UPSTREAM` | Base URL of `csp-booking-api` (scheme, host, port; no path). Default: `http://booking-api:8083`. |
| `APP_GATEWAY_WORKFLOW_UPSTREAM` | Base URL of `csp-workflow` (scheme, host, port; no path). Default: `http://workflow:8086`. |
| `APP_GATEWAY_TICKETING_UPSTREAM` | Base URL of `csp-ticketing-api` (scheme, host, port; no path). Default: `http://ticketing-api:8084`. |

See `.env.example`.

## TLS to Catalog (ADR-067)

Catalog serves HTTPS only, with a certificate issued by the internal CA of the environment (dev, qa, main).
The gateway calls it with `proxy_pass` over `https://` and verifies the certificate
(`nginx/templates/30-catalog-tls.conf.template`): `proxy_ssl_verify on`, only the CA file
`CATALOG_TLS_CA_FILE` is trusted (`proxy_ssl_trusted_certificate`), the name checked is `catalog-api`
(`proxy_ssl_name`, also sent as SNI), depth 2, TLS 1.2 or 1.3. The host in the URL does not change the name checked.

Fail closed: the script `nginx/entrypoint/05-require-catalog-tls.sh` runs from the image entrypoint before the
configuration is rendered. If `APP_GATEWAY_CATALOG_UPSTREAM` is not an `https://` URL, or the CA file is missing
or empty, it exits with an error and the container does not start. The check is at start, not per request: a
certificate that stops verifying later makes the Catalog routes answer 503. The CA private key is never here;
only the public certificate is mounted.

## Routes

| Path | Service | Authorization at the gateway |
|---|---|---|
| `/health` | the gateway itself | public |
| `/api/v1/auth/{register,register/confirm,login,refresh,forgot-password,reset-password,jwks,health,health/ready}` (login, register, register/confirm and forgot-password have a stricter rate limit, see below) | `csp-auth-api` | public |
| `/api/v1/auth/{logout,users,me,me/*,users/{userId}/role}` | `csp-auth-api` | header required (401 without it) |
| `/api/v1/auth/internal/*` | `csp-auth-api` | never exposed (404): `csp-worker` calls the service directly |
| `/api/v1/catalog/{billboard,billboard/movies}` (GET only) | `csp-catalog-api` | public |
| `/api/v1/catalog/{movies,rooms,showtimes}` (GET, POST) and `/api/v1/catalog/{movies,rooms,showtimes}/{id}` (GET, PATCH, DELETE) | `csp-catalog-api` | header required (401 without it) |
| `/api/v1/booking/{health,health/ready}` | `csp-booking-api` | public |
| `POST /api/v1/booking/holds`, `GET /api/v1/booking/reservations`, `GET /api/v1/booking/admin/reservations` (administrators; the service enforces `booking:read:all`), `GET /api/v1/booking/reservations/{id}`, `POST /api/v1/booking/reservations/{id}/confirm`, `GET /api/v1/booking/showtimes/{showtimeId}/seats` | `csp-booking-api` | header required (401 without it); another method is 404 |
| `/api/v1/booking/internal/*` | `csp-booking-api` | never exposed (404): `csp-worker` and `csp-workflow` call the service directly |
| `/api/v1/concessions/{health,health/ready}` | `csp-concessions-api` | public |
| `/api/v1/concessions/{products,combos,orders}` (GET, POST), `PATCH /api/v1/concessions/{products,combos}/{id}`, `GET /api/v1/concessions/orders/{id}`, `POST /api/v1/concessions/orders/{id}/cancel`, `POST /api/v1/concessions/stock/adjust` and `GET /api/v1/concessions/stock/movements` | `csp-concessions-api` | header required (401 without it) |
| `/api/v1/concessions/internal/*` | `csp-concessions-api` | never exposed (404): `csp-worker` calls the service directly |
| `POST /api/v1/sagas/book-seats`, `GET /api/v1/sagas/{id}` | `csp-workflow` | header required (401 without it); another method is 404 |
| `/api/v1/health` of the workflow | `csp-workflow` | never exposed (404) |
| `/api/v1/ticketing/{health,health/ready}` | `csp-ticketing-api` | public |
| `GET /api/v1/ticketing/me/tickets`, `GET /api/v1/ticketing/me/tickets/{ticketId}/pdf`, `GET /api/v1/ticketing/me/notifications` | `csp-ticketing-api` | header required (401 without it); another method is 404 |
| `/api/v1/ticketing/internal/*` | `csp-ticketing-api` | never exposed (404): `csp-worker` calls the service directly |

Anything else answers 404. The gateway only checks that `Authorization` is present; each service
validates the token.

## Rate limit

Stateless, per client IP (`limit_req_zone` in `nginx/templates/10-security.conf.template`), three zones.
Over the limit the gateway answers `429 TOO_MANY_REQUESTS` with `Retry-After: 1` (HU-AUTH-002, ADR-060).

| Zone | Rate | Burst | Routes |
|---|---|---|---|
| `per_client` | 10 r/s | 20 | every route except the credential routes below (`snippets/route-common.conf`) |
| `auth_credentials` | 2 r/s | 3 | `POST /api/v1/auth/login`, `POST /api/v1/auth/register` and `POST /api/v1/auth/register/confirm`: one bucket shared per IP |
| `auth_forgot` | 1 r/s | 2 | `/api/v1/auth/forgot-password` |

The credential routes use only their own zone (`routes/auth.conf`). The CORS preflight (`OPTIONS`) is
answered with 204 before any limit (`snippets/preflight.conf`). To tune, change the `rate` of the zone in the
template and the `burst` in the `limit_req` of the route, and extend the burst checks of `tests/smoke.sh`.

## Adding a domain

1. Add `APP_GATEWAY_<DOMAIN>_UPSTREAM` to `nginx/templates/20-upstreams.conf.template`, the
   Dockerfile, `deploy/compose.yml` and `.env.example`. Create `nginx/routes/<domain>.conf` with
   its `location` blocks and a **variable** in `proxy_pass` (`proxy_pass $<domain>_upstream;`) so
   the name is resolved per request. Start each proxied `location` with
   `snippets/route-common.conf` (preflight, rate limit) and add `snippets/require-auth.conf` to
   the protected ones.
2. Include `snippets/headers.conf` in any `location` that adds its own headers.
3. Extend `tests/smoke.sh`; the CI runs it on every Pull Request.

## Build, test, run

```bash
docker build -f deploy/Dockerfile -t gateway .
sh tests/support/make-ca.sh /tmp/gateway-tls        # throwaway CA for local runs
docker create --name gateway -p 8000:8000 gateway
docker cp /tmp/gateway-tls/ca.crt gateway:/run/tls/ca.crt
docker start gateway
sh tests/smoke.sh http://localhost:8000
sh tests/integration.sh                             # builds its own containers and CAs
```

With the platform, `CATALOG_TLS_CA_HOST_FILE=<ca.crt of the environment> docker compose -f deploy/compose.yml up -d`.

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
