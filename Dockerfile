FROM nginx:1.21.6
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=.conf
ENV NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx
ENV DEBUG_MODE=false
COPY nginx.conf /etc/nginx/templates/nginx.conf.conf

