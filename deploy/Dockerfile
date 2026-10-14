FROM nginx:1.27-alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/ /etc/nginx/conf.d/
COPY nginx/templates/ /etc/nginx/templates/
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/routes/ /etc/nginx/routes/
ENV APP_GATEWAY_CORS_ORIGIN_REGEX="http://localhost:(4200|4201|4202|4203|4204|4205)"
EXPOSE 8000
