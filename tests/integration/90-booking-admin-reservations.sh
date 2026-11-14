# Booking administrator list (GET /api/v1/booking/admin/reservations, booking-service.yaml 3.5.0): proxied with its query
# and the Authorization header, 401 without it, and the gateway's 404 for any other method or look-alike path.
# The permission booking:read:all is enforced by the service, not by the gateway.

ADMIN="$BASE_ECHO/api/v1/booking/admin/reservations"

fetch -X GET -H 'Authorization: Bearer t' "$ADMIN?page=1&limit=10&status=HELD"
expect "GET admin reservations reaches the booking upstream" "200" "$STATUS"
expect "GET admin reservations keeps the Authorization header" "Bearer t" "$(json_get authorization)"
fetch -X GET -H 'Authorization: Bearer t' -H 'X-User-Id: 99' "$ADMIN"
expect "an X-User-Id sent by the client is removed before booking" "" "$(json_get xUserId)"

fetch -X GET "$ADMIN"
expect "GET admin reservations without Authorization is 401" "401" "$STATUS"
expect "GET admin reservations without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"

not_routed() {  # method, path
  fetch -X "$1" -H 'Authorization: Bearer t' "$BASE_ECHO$2"
  expect "$1 $2 is the gateway's 404" "404" "$STATUS"
  expect "$1 $2 has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
}

not_routed POST "/api/v1/booking/admin/reservations"
not_routed PUT "/api/v1/booking/admin/reservations"
not_routed DELETE "/api/v1/booking/admin/reservations"
not_routed GET "/api/v1/booking/admin/reservations/"
not_routed GET "/api/v1/booking/admin/reservations/11111111-1111-4111-8111-111111111111"
not_routed GET "/api/v1/booking/admin"
