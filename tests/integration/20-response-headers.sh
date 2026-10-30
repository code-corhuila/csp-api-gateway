# D7: a browser from an allowed origin must be able to read the Retry-After of a 429.
# D9: the response carries exactly one X-Correlation-Id, even if the service sets its own.

origin='http://localhost:4201'
count_of() { printf '%s' "$2" | tr ',' '\n' | grep -ci "^ *$1 *$"; }

fetch -H "Origin: $origin" "$BASE_ECHO/api/v1/auth/jwks"
exposed=$(header_value Access-Control-Expose-Headers)
expect "the exposed headers include Retry-After" 1 "$(count_of Retry-After "$exposed")"
expect "the exposed headers still include X-Correlation-Id" 1 "$(count_of X-Correlation-Id "$exposed")"
expect "the exposed headers still include Location" 1 "$(count_of Location "$exposed")"

fetch_rate_limited "Origin: $origin"
expect "a burst from an allowed origin is rate limited" 429 "$STATUS"
expect "the 429 grants the allowed origin" "$origin" "$(header_value Access-Control-Allow-Origin)"
expect "the 429 exposes Retry-After to the browser" 1 "$(count_of Retry-After "$(header_value Access-Control-Expose-Headers)")"
expect "the 429 carries one Retry-After" 1 "$(header_count Retry-After)"
expect "the Retry-After value is 1 second" 1 "$(header_value Retry-After)"
expect "the 429 carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"

fetch_rate_limited 'Origin: http://evil.example'
expect "a burst from a foreign origin is rate limited" 429 "$STATUS"
expect "the 429 grants no access to a foreign origin" 0 "$(header_count Access-Control-Allow-Origin)"

fetch -H 'X-Correlation-Id: client-id-1' "$BASE_ECHO/api/v1/auth/jwks"
expect "a proxied response carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
expect "the client's id is the one returned" client-id-1 "$(header_value X-Correlation-Id)"
expect "the service received the client's id" client-id-1 "$(json_get correlationId)"

fetch "$BASE_ECHO/api/v1/auth/jwks"
generated=$(json_get correlationId)
expect "a proxied response without a client id carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
expect "the generated id is the one the service received" "$generated" "$(header_value X-Correlation-Id)"
expect "the generated id is not empty" 1 "$(printf '%s' "$generated" | grep -c '^[0-9a-f]\{32\}$')"

fetch -H 'X-Correlation-Id: client-id-2' "$BASE/nope"
expect "the gateway's 404 carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
fetch -X POST -H 'X-Correlation-Id: client-id-3' "$BASE/api/v1/auth/logout"
expect "the gateway's 401 carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
fetch -H 'X-Correlation-Id: client-id-4' "$BASE/api/v1/catalog/billboard"
expect "the gateway's 503 carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
fetch -X OPTIONS -H "Origin: $origin" -H 'X-Correlation-Id: client-id-5' "$BASE_ECHO/api/v1/auth/jwks"
expect "the preflight carries one X-Correlation-Id" 1 "$(header_count X-Correlation-Id)"
