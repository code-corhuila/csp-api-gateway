# D6: the gateway does not validate tokens and adds no X-User-* headers (ADR-028), so a client-supplied
# X-User-Id or X-User-Roles must never reach a service, on any proxied route.

routes="GET /api/v1/auth/jwks
POST /api/v1/auth/me/email
GET /api/v1/catalog/billboard
GET /api/v1/booking/health
POST /api/v1/booking/holds
GET /api/v1/booking/reservations
GET /api/v1/booking/showtimes/s1/seats"

echo "$routes" | while read -r method path; do
  fetch -X "$method" -H 'Authorization: Bearer t' -H 'X-User-Id: 999' -H 'X-User-Id: 998' -H 'x-user-roles: ADMIN' \
    -H 'X-User-Roles: CLIENT,ADMIN' "$BASE_ECHO$path"
  echo "$STATUS|$(json_get xUserId)|$(json_get xUserRoles)|$(json_get authorization)"
done > "$WORK/d6.out"
while IFS='|' read -r status user roles authorization; do
  expect "the route reaches the upstream" "200" "$status"
  expect "spoofed X-User-Id does not reach the service" "" "$user"
  expect "spoofed X-User-Roles does not reach the service" "" "$roles"
  expect "the Authorization header still reaches the service" "Bearer t" "$authorization"
done < "$WORK/d6.out"
expect "every route of the list was exercised" "7" "$(wc -l < "$WORK/d6.out" | tr -d ' ')"
