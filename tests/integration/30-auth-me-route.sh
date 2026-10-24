# HU-AUTH-007: the own profile (GET and PATCH /api/v1/auth/me) is routed to the auth service with the
# treatment of the other protected routes (Authorization required), while /me/email, /me/password
# and any look-alike path keep their behaviour.

for method in GET PATCH; do
  fetch -X "$method" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/auth/me"
  expect "$method /me reaches the auth upstream" "200" "$STATUS"
  expect "$method /me keeps the Authorization header" "Bearer t" "$(json_get authorization)"
  fetch -X "$method" "$BASE_ECHO/api/v1/auth/me"
  expect "$method /me without Authorization is 401" "401" "$STATUS"
  expect "$method /me without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"
done

for path in /api/v1/auth/me/email /api/v1/auth/me/password; do
  fetch -X POST -H 'Authorization: Bearer t' "$BASE_ECHO$path"
  expect "POST $path still reaches the auth upstream" "200" "$STATUS"
  fetch -X POST "$BASE_ECHO$path"
  expect "POST $path without Authorization is still 401" "401" "$STATUS"
done

for path in /api/v1/auth/me2 /api/v1/auth/mex /api/v1/auth/me/ /api/v1/auth/internal/me; do
  fetch -H 'Authorization: Bearer t' "$BASE_ECHO$path"
  expect "$path is the gateway's 404" "404" "$STATUS"
  expect "$path has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
done
