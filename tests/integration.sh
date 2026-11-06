#!/usr/bin/env sh
# Integration checks: real gateway containers built from this repository, in front of an upstream
# stub (tests/stub). Every tests/integration/*.sh file is run against them and the totals are printed.
# Usage: ./tests/integration.sh      (needs docker, curl and node)
# Optional: IT_PREFIX (container name prefix), IT_PORT (host port; the second gateway uses IT_PORT+1).
set -u
cd "$(dirname "$0")/.." || exit 1
PREFIX="${IT_PREFIX:-gwit-}"
PORT="${IT_PORT:-18000}"
NET="${PREFIX}net"
BASE="http://localhost:$PORT"
BASE_ECHO="http://localhost:$((PORT + 1))"
BASE_BADNAME="http://localhost:$((PORT + 2))"
BASE_BADCA="http://localhost:$((PORT + 3))"
WORK=""
passed=0
failed=0

cleanup() {
  docker rm -f "${PREFIX}gateway" "${PREFIX}gateway-echo" "${PREFIX}gateway-badname" "${PREFIX}gateway-badca" \
  "${PREFIX}stub" "${PREFIX}stub-tls" "${PREFIX}hang" "${PREFIX}tmp" >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  [ -n "$WORK" ] && rm -rf "$WORK"
}
trap "[ -n \"${KEEP:-}\" ] || cleanup" EXIT
cleanup
WORK=$(mktemp -d)

docker build -q -f deploy/Dockerfile -t "${PREFIX}gateway" . >/dev/null || exit 1
docker build -q -f tests/stub/Dockerfile -t "${PREFIX}stub" tests/stub >/dev/null || exit 1
docker network create "$NET" >/dev/null || exit 1

# Throwaway CAs and certificates for the HTTPS hop to the Catalog (ADR-067). Files are copied into the
# containers (docker cp), not bind-mounted, so the checks do not depend on the host's path conventions.
sh tests/support/make-ca.sh "$WORK/tls" || exit 1
# start_with_files NAME FILE:DEST[,FILE:DEST...] docker-run-args... : creates the container, copies the
# files (from $WORK/tls) to their absolute destinations, starts it.
start_with_files() {
  name="$1"; files="$2"; shift 2
  docker create --name "$name" "$@" >/dev/null || return 1
  for pair in $(printf '%s' "$files" | tr ',' ' '); do
    dest="${pair#*:}"
    mkdir -p "$WORK/stage/$name$(dirname "$dest")"
    cp "$WORK/tls/${pair%%:*}" "$WORK/stage/$name$dest"
  done
  # (Git Bash would rewrite "name:/" as a path; the arguments are relative to the staged tree.)
  (cd "$WORK/stage/$name" && MSYS2_ARG_CONV_EXCL="*" docker cp ./. "$name:/") || return 1
  docker start "$name" >/dev/null
}
CA_FILES="ca.crt:/run/tls/ca.crt"
cp tests/stub/echo-tls.conf "$WORK/tls/echo-tls.conf"
start_with_files "${PREFIX}stub-tls" \
  "server.crt:/run/tls/server.crt,server.key:/run/tls/server.key,wrong-name.crt:/run/tls/wrong-name.crt,wrong-name.key:/run/tls/wrong-name.key,untrusted.crt:/run/tls/untrusted.crt,untrusted.key:/run/tls/untrusted.key,echo-tls.conf:/etc/nginx/nginx.conf" \
  --network "$NET" "${PREFIX}stub" || exit 1
docker run -d --name "${PREFIX}stub" --network "$NET" "${PREFIX}stub" >/dev/null || exit 1
# An upstream that accepts the connection and never answers: the gateway times out (504).
docker run -d --name "${PREFIX}hang" --network "$NET" --entrypoint sh "${PREFIX}stub" \
  -c 'while true; do nc -l -p 80 >/dev/null 2>&1; done' >/dev/null || exit 1
# Gateway 1: auth -> stub (200), catalog -> stub-tls port 8083 (503), booking -> hang (504).
start_with_files "${PREFIX}gateway" "$CA_FILES" --network "$NET" -p "$PORT:8000" \
  -e "APP_GATEWAY_AUTH_UPSTREAM=http://${PREFIX}stub:80" \
  -e "APP_GATEWAY_CATALOG_UPSTREAM=https://${PREFIX}stub-tls:8083" \
  -e "APP_GATEWAY_BOOKING_UPSTREAM=http://${PREFIX}hang:80" \
  -e "APP_GATEWAY_CONCESSIONS_UPSTREAM=http://${PREFIX}stub:80" \
  -e "APP_GATEWAY_WORKFLOW_UPSTREAM=http://${PREFIX}stub:80" \
  "${PREFIX}gateway" || exit 1
# Gateway 2: every domain -> stub (200), to observe what reaches the upstream on each route; the catalog
# goes over verified TLS to stub-tls port 8082.
start_with_files "${PREFIX}gateway-echo" "$CA_FILES" --network "$NET" -p "$((PORT + 1)):8000" \
  -e "APP_GATEWAY_AUTH_UPSTREAM=http://${PREFIX}stub:80" \
  -e "APP_GATEWAY_CATALOG_UPSTREAM=https://${PREFIX}stub-tls:8082" \
  -e "APP_GATEWAY_BOOKING_UPSTREAM=http://${PREFIX}stub:80" \
  -e "APP_GATEWAY_CONCESSIONS_UPSTREAM=http://${PREFIX}stub:80" \
  -e "APP_GATEWAY_WORKFLOW_UPSTREAM=http://${PREFIX}stub:80" \
  "${PREFIX}gateway" || exit 1
# Gateway 3: trusts the right CA but Catalog presents a certificate for another name (stub-tls 8084).
start_with_files "${PREFIX}gateway-badname" "$CA_FILES" --network "$NET" -p "$((PORT + 2)):8000" \
  -e "APP_GATEWAY_CATALOG_UPSTREAM=https://${PREFIX}stub-tls:8084" \
  "${PREFIX}gateway" || exit 1
# Gateway 4: Catalog presents a certificate of an unrelated CA (stub-tls 8085), which this gateway does not trust.
start_with_files "${PREFIX}gateway-badca" "$CA_FILES" --network "$NET" -p "$((PORT + 3)):8000" \
  -e "APP_GATEWAY_CATALOG_UPSTREAM=https://${PREFIX}stub-tls:8085" \
  "${PREFIX}gateway" || exit 1

for url in "$BASE" "$BASE_ECHO" "$BASE_BADNAME" "$BASE_BADCA"; do
  tries=0
  until curl -s -o /dev/null "$url/health"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 40 ]; then echo "the gateway at $url did not start"; exit 1; fi
    sleep 0.5
  done
done

# --- helpers for the test files -------------------------------------------------------------

pass() { passed=$((passed + 1)); echo "  ok    $1"; }
fail() { failed=$((failed + 1)); echo "  FAIL  $1: $2"; }
expect() {  # description, wanted, got
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

# Runs a request and sets STATUS, HEAD (response headers) and BODY. Pauses so the per-client rate
# limit (10 requests/second) is never the reason for a failure.
fetch() {
  STATUS=$(curl -s -D "$WORK/last.head" -o "$WORK/last.body" -w '%{http_code}' "$@")
  HEAD=$(tr -d '\r' < "$WORK/last.head")
  BODY=$(cat "$WORK/last.body")
  sleep 0.15
}
header_count() { printf '%s\n' "$HEAD" | grep -ic "^$1:"; }
header_value() { printf '%s\n' "$HEAD" | grep -i "^$1:" | head -1 | sed 's/^[^:]*: *//'; }
json_keys() { printf '%s' "$BODY" | node tests/support/json.js keys; }
json_get() { printf '%s' "$BODY" | node tests/support/json.js get "$1"; }

# Sends 60 simultaneous requests to the first gateway so some are rate limited (the limit is 10
# requests/second with a burst of 20), keeps one 429 (sets STATUS, HEAD, BODY) and waits for the
# limiter to refill. The arguments are extra request headers ("Name: value") for every request.
fetch_rate_limited() {
  : > "$WORK/burst.cfg"
  i=0
  while [ "$i" -lt 60 ]; do
    {
      [ "$i" -gt 0 ] && echo "next"
      echo "url = \"$BASE/api/v1/auth/jwks\""
      echo "output = \"burst$i.body\""
      echo "dump-header = \"burst$i.head\""
      for header in "$@"; do
        printf 'header = "%s"\n' "$(printf '%s' "$header" | sed 's/[\\"]/\\&/g')"
      done
    } >> "$WORK/burst.cfg"
    i=$((i + 1))
  done
  (cd "$WORK" && curl -s --parallel --parallel-max 60 -K burst.cfg)
  STATUS=""; HEAD=""; BODY=""
  for head in "$WORK"/burst*.head; do
    if head -1 "$head" | grep -q ' 429'; then
      STATUS=429
      HEAD=$(tr -d '\r' < "$head")
      BODY=$(cat "${head%.head}.body")
      break
    fi
  done
  rm -f "$WORK"/burst*
  sleep 3
}

for file in tests/integration/*.sh; do
  echo "$file"
  # shellcheck disable=SC1090
  . "$file"
done

echo "integration checks: $passed passed, $failed failed"
[ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
