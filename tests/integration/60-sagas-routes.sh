# Sagas (/api/v1/sagas): the two operations of the workflow contract (workflow-service.yaml) are proxied with the
# method each declares and need the Authorization header; every other path or method, including the liveness
# probe of the workflow, is the gateway's 404.

ID=35920dc9-bd55-41a0-8e41-5832377383e5

route() {  # method, path, then the same path is checked without Authorization
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO$2"
  expect "$1 $2 reaches the workflow upstream" "200" "$STATUS"
  expect "$1 $2 keeps the Authorization header" "Bearer t" "$(json_get authorization)"
  fetch -X "$1" "$BASE_ECHO$2"
  expect "$1 $2 without Authorization is 401" "401" "$STATUS"
  expect "$1 $2 without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"
}

route POST "/api/v1/sagas/book-seats"
route GET "/api/v1/sagas/$ID"

fetch -X POST -H 'Authorization: Bearer t' -H 'X-Correlation-Id: it-saga-1' "$BASE_ECHO/api/v1/sagas/book-seats"
expect "the correlation id of the client reaches the workflow" "it-saga-1" "$(json_get correlationId)"
fetch -X POST -H 'Authorization: Bearer t' -H 'X-User-Id: 99' "$BASE_ECHO/api/v1/sagas/book-seats"
expect "an X-User-Id sent by the client is removed before the workflow" "" "$(json_get xUserId)"

not_routed() {  # method, path
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO$2"
  expect "$1 $2 is the gateway's 404" "404" "$STATUS"
  expect "$1 $2 has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
}

not_routed GET "/api/v1/sagas/book-seats"
not_routed PUT "/api/v1/sagas/book-seats"
not_routed DELETE "/api/v1/sagas/book-seats"
not_routed POST "/api/v1/sagas/$ID"
not_routed DELETE "/api/v1/sagas/$ID"
not_routed PATCH "/api/v1/sagas/$ID"
not_routed GET "/api/v1/sagas"
not_routed POST "/api/v1/sagas"
not_routed GET "/api/v1/sagas/"
not_routed GET "/api/v1/sagas/$ID/steps"
not_routed POST "/api/v1/sagas/book-seats/extra"
not_routed POST "/api/v1/sagasx/book-seats"
not_routed GET "/api/v1/health"
not_routed GET "/api/v1/workflow/health"

fetch -X OPTIONS -H 'Origin: http://localhost:4202' -H 'Access-Control-Request-Method: POST' "$BASE_ECHO/api/v1/sagas/book-seats"
expect "the preflight of the start of a saga is 204" "204" "$STATUS"
expect "the preflight allows Idempotency-Key" "1" "$(header_value Access-Control-Allow-Headers | grep -c 'Idempotency-Key')"
