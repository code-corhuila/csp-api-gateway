# Ticketing (/api/v1/ticketing): the client operations of the contract (ticketing-fulfillment-service.yaml) are proxied
# with the method each declares and need the Authorization header, the health routes are public, the internal
# operations are never exposed, and every other path or method is the gateway's 404.

ID=35920dc9-bd55-41a0-8e41-5832377383e5

route() {  # method, path: reaches the upstream with the header, and is 401 without it
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO$2"
  expect "$1 $2 reaches the ticketing upstream" "200" "$STATUS"
  expect "$1 $2 keeps the Authorization header" "Bearer t" "$(json_get authorization)"
  fetch -X "$1" "$BASE_ECHO$2"
  expect "$1 $2 without Authorization is 401" "401" "$STATUS"
  expect "$1 $2 without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"
}

route GET "/api/v1/ticketing/me/tickets"
route GET "/api/v1/ticketing/me/tickets/$ID/pdf"

for path in health health/ready; do
  fetch -X GET "$BASE_ECHO/api/v1/ticketing/$path"
  expect "GET /api/v1/ticketing/$path is public" "200" "$STATUS"
done

fetch -X GET -H 'Authorization: Bearer t' -H 'X-Correlation-Id: it-ticketing-1' "$BASE_ECHO/api/v1/ticketing/me/tickets"
expect "the correlation id of the client reaches ticketing" "it-ticketing-1" "$(json_get correlationId)"
fetch -X GET -H 'Authorization: Bearer t' -H 'X-User-Id: 99' "$BASE_ECHO/api/v1/ticketing/me/tickets"
expect "an X-User-Id sent by the client is removed before ticketing" "" "$(json_get xUserId)"

not_routed() {  # method, path
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO$2"
  expect "$1 $2 is the gateway's 404" "404" "$STATUS"
  expect "$1 $2 has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
}

not_routed POST "/api/v1/ticketing/me/tickets"
not_routed DELETE "/api/v1/ticketing/me/tickets"
not_routed POST "/api/v1/ticketing/me/tickets/$ID/pdf"
not_routed PUT "/api/v1/ticketing/me/tickets/$ID/pdf"
not_routed GET "/api/v1/ticketing/me/tickets/$ID"
not_routed GET "/api/v1/ticketing/me/tickets/$ID/pdf/extra"
not_routed GET "/api/v1/ticketing/me/tickets/"
not_routed GET "/api/v1/ticketing/me"
not_routed GET "/api/v1/ticketing"
not_routed GET "/api/v1/ticketing/"
not_routed GET "/api/v1/ticketingx/me/tickets"
not_routed GET "/api/v1/ticketing/internal/tickets/awaiting-pdf"
not_routed POST "/api/v1/ticketing/internal/tickets/$ID/pdf"
not_routed POST "/api/v1/ticketing/internal/fulfillments/dispatch"
not_routed GET "/api/v1/ticketing/internal"

fetch -X OPTIONS -H 'Origin: http://localhost:4205' -H 'Access-Control-Request-Method: GET' "$BASE_ECHO/api/v1/ticketing/me/tickets"
expect "the preflight of the tickets list is 204" "204" "$STATUS"
