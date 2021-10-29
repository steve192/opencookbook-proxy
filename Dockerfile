FROM nginx
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=.conf
ENV DEBUG_MODE=false
COPY nginx.conf /etc/nginx/templates/nginx.conf.conf

