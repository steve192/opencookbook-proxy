FROM nginx:1.27.0
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=.conf
ENV NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx
ENV DEBUG_MODE=false
ENV MAX_UPLOAD_SIZE_MB=30
COPY nginx.conf /etc/nginx/templates/nginx.conf.conf

