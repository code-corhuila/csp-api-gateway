#!/usr/bin/env sh
# The checks the gateway must pass. Usage: ./tests/smoke.sh http://localhost:8000
# Checks that need a domain route (401, 429, 503, preflight) arrive with the first route.
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

exit $fail
