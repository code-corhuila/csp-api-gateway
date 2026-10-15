# Changelog

All notable changes to this repository are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
