# The Catalog hop is HTTPS with verification (ADR-067, section 3; code-corhuila/csp-docs#289, criterion 2):
# the generated configuration verifies the certificate against the internal CA and the name `catalog-api`,
# a certificate of another name or of another CA is refused (503), and the gateway refuses to start with
# an http:// Catalog upstream or without the CA file.

config=$(docker exec "${PREFIX}gateway-echo" nginx -T 2>&1)
has_directive() { printf '%s\n' "$config" | grep -c "^$1;" ; }
expect "the configuration is valid with the CA file" "0" "$(docker exec "${PREFIX}gateway-echo" nginx -t >/dev/null 2>&1; echo $?)"
expect "the generated config verifies the upstream certificate" "1" "$(has_directive 'proxy_ssl_verify on')"
expect "the generated config trusts only the CA file" "1" "$(has_directive 'proxy_ssl_trusted_certificate /run/tls/ca.crt')"
expect "the generated config checks the name catalog-api" "1" "$(has_directive 'proxy_ssl_name catalog-api')"
expect "the generated config sends the name as SNI" "1" "$(has_directive 'proxy_ssl_server_name on')"
expect "the generated config never turns verification off" "0" "$(printf '%s\n' "$config" | grep -c 'proxy_ssl_verify off')"

fetch "$BASE_ECHO/api/v1/catalog/billboard"
expect "a certificate of the internal CA for catalog-api is accepted (200)" "200" "$STATUS"
fetch "$BASE_BADNAME/api/v1/catalog/billboard"
expect "a certificate for another name is refused (503)" "503" "$STATUS"
expect "the refusal is a name mismatch in the log" "1" "$(docker logs "${PREFIX}gateway-badname" 2>&1 | grep -c "upstream SSL certificate does not match \"catalog-api\"")"
fetch "$BASE_BADCA/api/v1/catalog/billboard"
expect "a certificate of another CA is refused (503)" "503" "$STATUS"
expect "the refusal is a failed verification in the log" "1" "$(docker logs "${PREFIX}gateway-badca" 2>&1 | grep -c 'upstream SSL certificate verify error')"

# Fail closed: `docker run` without the CA file, or with an http:// upstream, exits before nginx starts.
out=$(docker run --rm "${PREFIX}gateway" nginx -t 2>&1); code=$?
expect "without the CA file the gateway does not start" "1" "$code"
expect "the missing CA file is named" "1" "$(printf '%s\n' "$out" | grep -c 'CATALOG_TLS_CA_FILE must point to a non-empty CA')"
name="${PREFIX}tmp"
docker rm -f "$name" >/dev/null 2>&1
docker create --name "$name" -e "APP_GATEWAY_CATALOG_UPSTREAM=http://catalog-api:8082" "${PREFIX}gateway" nginx -t >/dev/null
mkdir -p "$WORK/stage/http/run/tls" && cp "$WORK/tls/ca.crt" "$WORK/stage/http/run/tls/"
(cd "$WORK/stage/http" && MSYS2_ARG_CONV_EXCL="*" docker cp ./. "$name:/")
out=$(docker start -a "$name" 2>&1); code=$?
docker rm -f "$name" >/dev/null 2>&1
expect "with an http:// Catalog upstream the gateway does not start" "1" "$code"
expect "the http:// upstream is named" "1" "$(printf '%s\n' "$out" | grep -c 'must be an https:// URL')"
