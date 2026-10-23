FROM nginx:1.27-alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/ /etc/nginx/conf.d/
COPY nginx/templates/ /etc/nginx/templates/
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/routes/ /etc/nginx/routes/
ENV APP_GATEWAY_CORS_ORIGIN_REGEX="http://localhost:(4200|4201|4202|4203|4204|4205)"
ENV APP_GATEWAY_AUTH_UPSTREAM="http://auth-api:8081"
ENV APP_GATEWAY_CATALOG_UPSTREAM="http://catalog-api:8082"
ENV APP_GATEWAY_BOOKING_UPSTREAM="http://booking-api:8083"
EXPOSE 8000
