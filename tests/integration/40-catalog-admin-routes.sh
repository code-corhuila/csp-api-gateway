# Catalog administration (/movies, /rooms, /showtimes): each route is proxied with the method the
# contract declares, needs the Authorization header, forwards Idempotency-Key, and every other path or
# method, including the availability of a showtime (service-to-service), is the gateway's 404.

for resource in movies rooms showtimes; do
  for method in GET POST; do
    fetch -X "$method" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/catalog/$resource"
    expect "$method /$resource reaches the catalog upstream" "200" "$STATUS"
    expect "$method /$resource keeps the Authorization header" "Bearer t" "$(json_get authorization)"
    fetch -X "$method" "$BASE_ECHO/api/v1/catalog/$resource"
    expect "$method /$resource without Authorization is 401" "401" "$STATUS"
    expect "$method /$resource without Authorization has the common envelope" "UNAUTHORIZED" "$(json_get error)"
  done
  for method in GET PATCH DELETE; do
    fetch -X "$method" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/catalog/$resource/0b1f6f0e-0000-4000-8000-000000000001"
    expect "$method /$resource/{id} reaches the catalog upstream" "200" "$STATUS"
    fetch -X "$method" "$BASE_ECHO/api/v1/catalog/$resource/0b1f6f0e-0000-4000-8000-000000000001"
    expect "$method /$resource/{id} without Authorization is 401" "401" "$STATUS"
  done
  for method in PUT DELETE; do
    fetch -X "$method" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/catalog/$resource"
    expect "$method /$resource is the gateway's 404" "404" "$STATUS"
  done
  for method in POST PUT; do
    fetch -X "$method" -H 'Authorization: Bearer t' "$BASE_ECHO/api/v1/catalog/$resource/0b1f6f0e-0000-4000-8000-000000000001"
    expect "$method /$resource/{id} is the gateway's 404" "404" "$STATUS"
  done
done

fetch -X OPTIONS -H 'Origin: http://localhost:4200' -H 'Access-Control-Request-Method: PATCH' "$BASE_ECHO/api/v1/catalog/movies/0b1f6f0e-0000-4000-8000-000000000001"
expect "the preflight of a catalog write is 204" "204" "$STATUS"
expect "the preflight allows Idempotency-Key" "1" "$(header_value Access-Control-Allow-Headers | grep -c 'Idempotency-Key')"

for path in /api/v1/catalog/showtimes/0b1f6f0e-0000-4000-8000-000000000001/availability \
            /api/v1/catalog/movies/0b1f6f0e-0000-4000-8000-000000000001/extra \
            /api/v1/catalog/movies/ /api/v1/catalog/moviesx /api/v1/catalog/health; do
  fetch -H 'Authorization: Bearer t' "$BASE_ECHO$path"
  expect "$path is the gateway's 404" "404" "$STATUS"
  expect "$path has the NOT_FOUND envelope" "NOT_FOUND" "$(json_get error)"
done
