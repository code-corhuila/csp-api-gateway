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
check    "user list without Authorization is 401"          401 "$BASE$AUTH/users?email=a@b.c&page=1&limit=10"
check    "role change (PATCH) without Authorization is 401" 401 -X PATCH "$BASE$AUTH/users/1/role"
contains "401 uses the error envelope"             '"error":"UNAUTHORIZED"' -X POST "$BASE$AUTH/logout"
check    "logout with Authorization reaches the service"   503 -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/logout"
check    "user list with Authorization is routed with its query" 503 -H 'Authorization: Bearer x' "$BASE$AUTH/users?email=a@b.c&page=1&limit=10"
check    "role change (PATCH) with Authorization is routed" 503 -X PATCH -H 'Authorization: Bearer x' "$BASE$AUTH/users/1/role"
check    "internal purge is not exposed"                   404 -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/internal/maintenance/purge"
contains "internal purge answers the error envelope" '"error":"NOT_FOUND"' -X POST -H 'Authorization: Bearer x' "$BASE$AUTH/internal/maintenance/purge"
check    "an operation outside the contract is 404"        404 "$BASE$AUTH/nope"
check    "preflight of a protected route is answered"      204 -X OPTIONS -H 'Origin: http://localhost:4201' -H 'Access-Control-Request-Method: PATCH' "$BASE$AUTH/users/1/role"
contains "preflight allows PATCH"                  'Access-Control-Allow-Methods: .*PATCH' -X OPTIONS -H 'Origin: http://localhost:4201' "$BASE$AUTH/users/1/role"
contains "an error of a route keeps the correlation id" 'X-Correlation-Id: smoke-2' -X POST -H 'X-Correlation-Id: smoke-2' "$BASE$AUTH/logout"

CATALOG=/api/v1/catalog
check    "public billboard passes without Authorization"       503 "$BASE$CATALOG/billboard"
check    "public billboard is routed with its query"           503 "$BASE$CATALOG/billboard?date=2026-11-01&movieId=1&page=1&limit=10"
check    "public movie search passes without Authorization"    503 "$BASE$CATALOG/billboard/movies"
check    "public movie search is routed with its filters"      503 "$BASE$CATALOG/billboard/movies?q=space%20action&genre=Drama&durationMax=120&page=1&limit=10"
check    "a token sent to a public read is not refused"        503 -H 'Authorization: Bearer x' "$BASE$CATALOG/billboard"
check    "only GET is routed on the billboard"                 404 -X POST -H 'Authorization: Bearer x' "$BASE$CATALOG/billboard"
check    "only GET is routed on the movie search"              404 -X DELETE -H 'Authorization: Bearer x' "$BASE$CATALOG/billboard/movies"
check    "a path under the billboard is 404"                   404 "$BASE$CATALOG/billboard/extra"
check    "a trailing slash is 404"                             404 "$BASE$CATALOG/billboard/movies/"
check    "the movie administration is not routed yet"          404 -H 'Authorization: Bearer x' "$BASE$CATALOG/movies"
check    "the room administration is not routed yet"           404 -H 'Authorization: Bearer x' "$BASE$CATALOG/rooms"
check    "the showtime administration is not routed yet"       404 -H 'Authorization: Bearer x' "$BASE$CATALOG/showtimes"
check    "the availability of a showtime is not exposed"       404 -H 'Authorization: Bearer x' "$BASE$CATALOG/showtimes/1/availability"
check    "a route of the catalog outside the contract is 404"  404 "$BASE$CATALOG/nope"
contains "a 404 of the catalog keeps the error envelope"       '"error":"NOT_FOUND"' -X POST "$BASE$CATALOG/billboard"
check    "preflight of the billboard is answered"              204 -X OPTIONS -H 'Origin: http://localhost:4203' -H 'Access-Control-Request-Method: GET' "$BASE$CATALOG/billboard"
check    "preflight of the movie search is answered"           204 -X OPTIONS -H 'Origin: http://localhost:4203' -H 'Access-Control-Request-Method: GET' "$BASE$CATALOG/billboard/movies"
contains "the catalog portal origin is allowed"                'Access-Control-Allow-Origin: http://localhost:4203' -H 'Origin: http://localhost:4203' "$BASE$CATALOG/billboard/movies"
absent   "an unknown origin gets no grant on the movie search" 'Access-Control-Allow-Origin' -H 'Origin: http://evil.example' "$BASE$CATALOG/billboard/movies"
contains "an error of a catalog route keeps the correlation id" 'X-Correlation-Id: smoke-3' -H 'X-Correlation-Id: smoke-3' "$BASE$CATALOG/billboard"

BOOKING=/api/v1/booking
RES=11111111-1111-4111-8111-111111111111
SHOWTIME=33333333-3333-4333-8333-333333333333
check    "booking health passes without Authorization"         503 "$BASE$BOOKING/health"
check    "booking readiness passes without Authorization"      503 "$BASE$BOOKING/health/ready"
check    "a hold without Authorization is 401"                 401 -X POST "$BASE$BOOKING/holds"
check    "a hold with Authorization reaches the service"       503 -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/holds"
check    "only POST is routed on the holds"                    404 -H 'Authorization: Bearer x' "$BASE$BOOKING/holds"
check    "the list of reservations without Authorization is 401" 401 "$BASE$BOOKING/reservations?page=1&limit=10"
check    "the list of reservations is routed with its query"   503 -H 'Authorization: Bearer x' "$BASE$BOOKING/reservations?page=1&limit=10&status=HELD"
check    "only GET is routed on the list of reservations"      404 -X DELETE -H 'Authorization: Bearer x' "$BASE$BOOKING/reservations"
check    "a reservation without Authorization is 401"          401 "$BASE$BOOKING/reservations/$RES"
check    "a reservation with Authorization reaches the service" 503 -H 'Authorization: Bearer x' "$BASE$BOOKING/reservations/$RES"
check    "a confirmation without Authorization is 401"         401 -X POST "$BASE$BOOKING/reservations/$RES/confirm"
check    "a confirmation with Authorization reaches the service" 503 -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/reservations/$RES/confirm"
check    "only POST is routed on the confirmation"             404 -H 'Authorization: Bearer x' "$BASE$BOOKING/reservations/$RES/confirm"
check    "the seat map without Authorization is 401"           401 "$BASE$BOOKING/showtimes/$SHOWTIME/seats"
check    "the seat map with Authorization reaches the service" 503 -H 'Authorization: Bearer x' "$BASE$BOOKING/showtimes/$SHOWTIME/seats"
check    "only GET is routed on the seat map"                  404 -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/showtimes/$SHOWTIME/seats"
check    "a path under the seat map is 404"                    404 -H 'Authorization: Bearer x' "$BASE$BOOKING/showtimes/$SHOWTIME/seats/A1"
check    "the maintenance operations are not exposed"          404 -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/internal/maintenance/expire-holds"
check    "the workflow operations are not exposed"             404 -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/internal/workflow/holds"
contains "an internal operation answers the error envelope"    '"error":"NOT_FOUND"' -X POST -H 'Authorization: Bearer x' "$BASE$BOOKING/internal/maintenance/purge"
check    "a route of booking outside the contract is 404"      404 "$BASE$BOOKING/nope"
contains "a 401 of booking uses the error envelope"            '"error":"UNAUTHORIZED"' -X POST "$BASE$BOOKING/holds"
check    "preflight of a hold is answered"                     204 -X OPTIONS -H 'Origin: http://localhost:4202' -H 'Access-Control-Request-Method: POST' "$BASE$BOOKING/holds"
contains "preflight allows the Idempotency-Key of a hold"      'Access-Control-Allow-Headers: .*Idempotency-Key' -X OPTIONS -H 'Origin: http://localhost:4202' "$BASE$BOOKING/holds"
contains "the booking portal origin is allowed"                'Access-Control-Allow-Origin: http://localhost:4202' -H 'Origin: http://localhost:4202' "$BASE$BOOKING/showtimes/$SHOWTIME/seats"
absent   "an unknown origin gets no grant on the seat map"     'Access-Control-Allow-Origin' -H 'Origin: http://evil.example' "$BASE$BOOKING/showtimes/$SHOWTIME/seats"
contains "an error of a booking route keeps the correlation id" 'X-Correlation-Id: smoke-4' -X POST -H 'X-Correlation-Id: smoke-4' "$BASE$BOOKING/holds"

# Rate limit of the credential routes: login and register share one bucket per client (2 r/s, burst 3),
# forgot-password has its own (1 r/s, burst 2), and no other route is affected. The buckets are
# per client IP, so each step pauses until the previous burst has drained.
flood() {  # method, urls... : every response, headers included
  method="$1"; shift
  curl -s -i --parallel --parallel-max 20 -X "$method" "$@"
}

repeat() {  # count, url : the url repeated count times
  for i in $(seq 1 "$1"); do printf '%s ' "$2"; done
}

limited() {  # responses on stdin : how many are 429
  grep -c '^HTTP/[0-9.]* 429'
}

expect_limited() {  # description, responses
  n=$(printf '%s\n' "$2" | limited)
  if [ "$n" -gt 0 ]; then echo "  ok    $1 ($n x 429)"; else echo "  FAIL  $1: no 429"; fail=1; fi
}

expect_not_limited() {  # description, responses
  n=$(printf '%s\n' "$2" | limited)
  if [ "$n" -eq 0 ]; then echo "  ok    $1"; else echo "  FAIL  $1: $n x 429"; fail=1; fi
}

sleep 3
# shellcheck disable=SC2046
login_flood=$(flood POST $(repeat 10 "$BASE$AUTH/login"))
expect_limited "a burst of logins is rate limited" "$login_flood"
if printf '%s\n' "$login_flood" | grep -qi '^Retry-After: 1'; then echo "  ok    the 429 of login carries Retry-After"; else echo "  FAIL  the 429 of login carries Retry-After: missing"; fail=1; fi
check    "preflight of login is answered while the bucket is exhausted" 204 -X OPTIONS -H 'Origin: http://localhost:4201' -H 'Access-Control-Request-Method: POST' "$BASE$AUTH/login"
contains "preflight of login keeps the CORS headers while the bucket is exhausted" 'Access-Control-Allow-Origin: http://localhost:4201' -X OPTIONS -H 'Origin: http://localhost:4201' "$BASE$AUTH/login"
# shellcheck disable=SC2046
expect_not_limited "another route keeps its own limit while login is exhausted" "$(flood GET $(repeat 8 "$BASE$AUTH/jwks"))"
sleep 3
check    "a login after a pause is not rate limited"        503 -X POST "$BASE$AUTH/login"

sleep 3
# shellcheck disable=SC2046
expect_limited "login and register share one bucket" "$(flood POST $(repeat 4 "$BASE$AUTH/login") $(repeat 4 "$BASE$AUTH/register"))"

sleep 3
# shellcheck disable=SC2046
expect_limited "a burst of registrations is rate limited" "$(flood POST $(repeat 10 "$BASE$AUTH/register"))"
sleep 3
check    "a registration after a pause is not rate limited" 503 -X POST "$BASE$AUTH/register"

sleep 3
# shellcheck disable=SC2046
flood POST $(repeat 10 "$BASE$AUTH/login") >/dev/null
check    "forgot-password has a bucket of its own while login is exhausted" 503 -X POST "$BASE$AUTH/forgot-password"
sleep 3
# shellcheck disable=SC2046
forgot_flood=$(flood POST $(repeat 10 "$BASE$AUTH/forgot-password"))
expect_limited "a burst of forgot-password is rate limited" "$forgot_flood"
if printf '%s\n' "$forgot_flood" | grep -qi '^Retry-After: 1'; then echo "  ok    the 429 of forgot-password carries Retry-After"; else echo "  FAIL  the 429 of forgot-password carries Retry-After: missing"; fail=1; fi

sleep 3
# Rate limit of every other route: a burst of 60 simultaneous requests from one client exceeds the burst of 20.
burst=$(for i in $(seq 1 60); do printf '%s?n=%s ' "$BASE$AUTH/jwks" "$i"; done)
# shellcheck disable=SC2086
limited=$(curl -s --parallel --parallel-max 60 -w '\n%{http_code}\n' $burst | grep -c '^429$')
if [ "$limited" -gt 0 ]; then echo "  ok    a burst of requests is rate limited (429)"; else echo "  FAIL  a burst of requests is rate limited: no 429"; fail=1; fi

exit $fail
