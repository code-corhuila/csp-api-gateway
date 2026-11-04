# Concessions (/products, /combos, /orders, /stock): each operation of the contract is proxied with the
# method it declares, needs the Authorization header, and every other path or
# method, including the internal operations of csp-worker, is the gateway's 404.

ID=0b1f6f0e-0000-4000-8000-000000000001

for path in health health/ready; do
  fetch "$BASE_ECHO/api/v1/concessions/$path"
  expect "GET /$path reaches the concessions upstream without Authorization" "200" "$STATUS"
done

route() {  # method, path (after /api/v1/concessions), then the same path is checked without Authorization
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/concessions$2"
  expect "$1 $2 reaches the concessions upstream" "200" "$STATUS"
  expect "$1 $2 keeps the Authorization header" "Bearer t" "$(json_get authorization)"
  fetch -X "$1" "$BASE_ECHO/api/v1/concessions$2"
  expect "$1 $2 without Authorization is 401" "401" "$STATUS"
  expect "$1 $2 without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"
}

for collection in products combos orders; do
  route GET "/$collection"
  route POST "/$collection"
done
route PATCH "/products/$ID"
route PATCH "/combos/$ID"
route GET "/orders/$ID"
route POST "/orders/$ID/cancel"
route POST "/stock/adjust"
route GET "/stock/movements"

not_routed() {  # method, path
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/concessions$2"
  expect "$1 $2 is the gateway's 404" "404" "$STATUS"
  expect "$1 $2 has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
}

for collection in products combos orders; do
  not_routed PUT "/$collection"
  not_routed DELETE "/$collection"
done
for item in products combos; do
  not_routed GET "/$item/$ID"
  not_routed DELETE "/$item/$ID"
done
not_routed POST "/orders/$ID"
not_routed GET "/orders/$ID/cancel"
not_routed GET "/stock/adjust"
not_routed POST "/stock/movements"
not_routed POST "/internal/orders/expire"
not_routed POST "/internal/orders/by-reservation/$ID/confirm"
not_routed POST "/internal/maintenance/purge"
not_routed GET "/products/"
not_routed GET "/productsx"
not_routed GET "/nope"

fetch -X OPTIONS -H 'Origin: http://localhost:4204' -H 'Access-Control-Request-Method: PATCH' "$BASE_ECHO/api/v1/concessions/products/$ID"
expect "the preflight of a concessions write is 204" "204" "$STATUS"
expect "the preflight allows Idempotency-Key" "1" "$(header_value Access-Control-Allow-Headers | grep -c 'Idempotency-Key')"
