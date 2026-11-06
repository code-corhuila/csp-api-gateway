FROM nginx:1.27-alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/ /etc/nginx/conf.d/
COPY nginx/templates/ /etc/nginx/templates/
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/routes/ /etc/nginx/routes/
COPY nginx/entrypoint/ /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/05-require-catalog-tls.sh && mkdir -p /run/tls
ENV APP_GATEWAY_CORS_ORIGIN_REGEX="http://localhost:(4200|4201|4202|4203|4204|4205)"
ENV APP_GATEWAY_AUTH_UPSTREAM="http://auth-api:8081"
ENV APP_GATEWAY_CATALOG_UPSTREAM="https://catalog-api:8082"
ENV CATALOG_TLS_CA_FILE="/run/tls/ca.crt"
ENV APP_GATEWAY_BOOKING_UPSTREAM="http://booking-api:8083"
ENV APP_GATEWAY_CONCESSIONS_UPSTREAM="http://concessions-api:8085"
ENV APP_GATEWAY_WORKFLOW_UPSTREAM="http://workflow:8086"
EXPOSE 8000
