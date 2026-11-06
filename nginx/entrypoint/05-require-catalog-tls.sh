#!/bin/sh
# Fail closed (ADR-067): the gateway does not start unless the Catalog upstream is https:// and the CA
# file that verifies it exists. Run by the nginx image entrypoint before the templates are rendered,
# so a rejected configuration never reaches `nginx -t` or the worker processes.
set -eu

upstream="${APP_GATEWAY_CATALOG_UPSTREAM:-}"
ca_file="${CATALOG_TLS_CA_FILE:-}"

case "$upstream" in
  https://?*) ;;
  *)
    echo "05-require-catalog-tls: APP_GATEWAY_CATALOG_UPSTREAM must be an https:// URL (got '${upstream}')" >&2
    exit 1
    ;;
esac

if [ -z "$ca_file" ] || [ ! -s "$ca_file" ]; then
  echo "05-require-catalog-tls: CATALOG_TLS_CA_FILE must point to a non-empty CA certificate file (got '${ca_file}')" >&2
  exit 1
fi
