#!/usr/bin/env sh
# The checks the gateway must pass. Usage: ./tests/smoke.sh http://localhost:8000
# The auth service is not running here: a request that passes the gateway answers 503.
set -u
BASE="${1:-http://localhost:8000}"
fail=0

check() {  # description, expected status, curl arguments...
  desc="$1"; want="$2"; shift 2
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ]; then echo "  ok    $desc ($got)"; else echo "  FAIL  $desc: want $want, got $got"; fail=1; fi
}

contains() {  # description, expected text, curl arguments...
  desc="$1"; want="$2"; shift 2
  if curl -s -i "$@" | grep -qi -- "$want"; then echo "  ok    $desc"; else echo "  FAIL  $desc: missing $want"; fail=1; fi
}

absent() {  # description, forbidden text, curl arguments...
  desc="$1"; bad="$2"; shift 2
  if curl -s -i "$@" | grep -qi -- "$bad"; then echo "  FAIL  $desc: found $bad"; fail=1; else echo "  ok    $desc"; fi
}

check    "health answers"                          200 "$BASE/health"
check    "unknown route is 404"                    404 "$BASE/nope"
contains "404 uses the error envelope"             '"error":"NOT_FOUND"' "$BASE/nope"
contains "a correlation id is generated"           'X-Correlation-Id:' "$BASE/health"
contains "the client's correlation id is kept"     'X-Correlation-Id: smoke-1' -H 'X-Correlation-Id: smoke-1' "$BASE/health"
contains "the shell origin is allowed"             'Access-Control-Allow-Origin: http://localhost:4200' -H 'Origin: http://localhost:4200' "$BASE/health"
contains "a remote origin is allowed"              'Access-Control-Allow-Origin: http://localhost:4205' -H 'Origin: http://localhost:4205' "$BASE/health"
contains "CORS exposes X-Correlation-Id"           'Access-Control-Expose-Headers: X-Correlation-Id' -H 'Origin: http://localhost:4200' "$BASE/health"
contains "CORS allows Idempotency-Key"             'Idempotency-Key' -H 'Origin: http://localhost:4200' "$BASE/health"
absent   "an unknown origin gets no CORS grant"    'Access-Control-Allow-Origin' -H 'Origin: http://evil.example' "$BASE/health"
absent   "a lookalike origin (port suffix) is rejected"   'Access-Control-Allow-Origin' -H 'Origin: http://localhost:42000' "$BASE/health"
absent   "a lookalike origin (host suffix) is rejected"   'Access-Control-Allow-Origin' -H 'Origin: http://localhost:4200.evil.com' "$BASE/health"

AUTH=/api/v1/auth
check    "public register passes without Authorization"    503 -X POST "$BASE$AUTH/register"
check    "public login passes without Authorization"       503 -X POST "$BASE$AUTH/login"
check    "public refresh passes without Authorization"     503 -X POST "$BASE$AUTH/refresh"
check    "public forgot-password passes without Authorization" 503 -X POST "$BASE$AUTH/forgot-password"
check    "public reset-password passes without Authorization"  503 -X POST "$BASE$AUTH/reset-password"
check    "public jwks passes without Authorization"        503 "$BASE$AUTH/jwks"
check    "public health passes without Authorization"      503 "$BASE$AUTH/health"
check    "public readiness passes without Authorization"   503 "$BASE$AUTH/health/ready"
check    "logout without Authorization is 401"             401 -X POST "$BASE$AUTH/logout"
check    "email change without Authorization is 401"       401 -X POST "$BASE$AUTH/me/email"
check    "email verify without Authorization is 401"       401 -X POST "$BASE$AUTH/me/email/verify"
check    "role change (PATCH) without Authorization is 401" 401 -X PATCH "$BASE$AUTH/users/1/role"
contains "401 uses the error envelope"             '"error":"UNAUTHORIZED"' -X POST "$BASE$AUTH/logout"
check    "logout with Authorization reaches the service"   503 -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/logout"
check    "role change (PATCH) with Authorization is routed" 503 -X PATCH -H 'Authorization: Bearer x' "$BASE$AUTH/users/1/role"
check    "internal purge is not exposed"                   404 -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/internal/maintenance/purge"
contains "internal purge answers the error envelope" '"error":"NOT_FOUND"' -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/internal/maintenance/purge"
check    "an operation outside the contract is 404"        404 "$BASE$AUTH/nope"
check    "preflight of a protected route is answered"      204 -X OPTIONS -H 'Origin: http://localhost:4201' -H 'Access-Control-Request-Method: PATCH' "$BASE$AUTH/users/1/role"
contains "preflight allows PATCH"                  'Access-Control-Allow-Methods: .*PATCH' -X OPTIONS -H 'Origin: http://localhost:4201' "$BASE$AUTH/users/1/role"
contains "an error of a route keeps the correlation id" 'X-Correlation-Id: smoke-2' -X POST -H 'X-Correlation-Id: smoke-2' "$BASE$AUTH/logout"

# Rate limit: a burst of 60 simultaneous requests from one client exceeds the burst of 20.
burst=$(for i in $(seq 1 60); do printf '%s?n=%s ' "$BASE$AUTH/jwks" "$i"; done)
# shellcheck disable=SC2086
limited=$(curl -s --parallel --parallel-max 60 -w '\n%{http_code}\n' $burst | grep -c '^429$')
if [ "$limited" -gt 0 ]; then echo "  ok    a burst of requests is rate limited (429)"; else echo "  FAIL  a burst of requests is rate limited: no 429"; fail=1; fi

exit $fail
