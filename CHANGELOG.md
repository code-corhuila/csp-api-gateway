# Changelog

All notable changes to this repository are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Strip the client-supplied `X-User-Id` and `X-User-Roles` request headers before proxying, on every route (HU-AUTH-004, D6). The gateway does not validate tokens and adds no `X-User-*` headers (ADR-028), so it only strips them.
- Expose `Retry-After` in `Access-Control-Expose-Headers`, so a browser from an allowed origin can read the `Retry-After` of a 429 (HU-AUTH-004, D7).
- Answer with exactly one `X-Correlation-Id`: the one a service sets is hidden and the gateway's own is sent (HU-AUTH-004, D9).
- Reflect the client `X-Correlation-Id` (response header, `traceId` of the gateway errors, service request, access log) only when it matches `^[A-Za-z0-9._-]{1,64}$`; otherwise the gateway generates one. A quote or backslash no longer injects fields or breaks the JSON of the errors the gateway writes (HU-AUTH-004, D8).

### Added
- Integration checks against real gateway containers and an upstream stub (`tests/integration.sh`), run by `ci.yml`.
- Route `/api/v1/booking/` to `csp-booking-api` (HU-CATALOG-005, `booking-service.yaml` 3.3.0): the health routes are public; `POST /holds`, `GET /reservations`, `GET /reservations/{id}`, `POST /reservations/{id}/confirm` and `GET /showtimes/{showtimeId}/seats` require the presence of `Authorization` and only their own method is routed; `/internal/*` (maintenance and workflow) is never exposed and any other path is the gateway's 404. New variable `APP_GATEWAY_BOOKING_UPSTREAM` (default `http://booking-api:8083`).
- Route `/api/v1/catalog/` to `csp-catalog-api` (HU-FE-CATALOG-002): the two public reads of the contract,
  `GET /billboard` and `GET /billboard/movies`, pass without `Authorization` and any other path or method
  under it is the gateway's 404 (the administration routes and the availability of a showtime are not exposed).
  New variable `APP_GATEWAY_CATALOG_UPSTREAM` (default `http://catalog-api:8082`).
- Base scaffold of the declarative NGINX gateway (Annex F): `nginx/` configuration,
  `deploy/Dockerfile` and `deploy/compose.yml` (service `api-gateway`, port 8000),
  `tests/smoke.sh` and the `ci.yml` pipeline.
- Stateless per-IP rate limiting (`limit_req`), anchored CORS origin regex rendered from
  `APP_GATEWAY_CORS_ORIGIN_REGEX`, `X-Correlation-Id` handling and the shared error envelope.
- `/health` of the gateway itself.
- Route `/api/v1/auth/` to `csp-auth-api` (HU-AUTH-003): public operations pass without
  `Authorization`, `logout`, `/users`, `/me/*` and `/users/{userId}/role` require its presence, and
  `/api/v1/auth/internal/` is not exposed. The upstream is `APP_GATEWAY_AUTH_UPSTREAM`
  (default `http://auth-api:8081`). CORS preflight is answered by the gateway and the rate limit
  applies to the route.
