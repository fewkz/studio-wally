FROM openresty/openresty:1.21.4.1-0-alpine

RUN apk add --no-cache curl perl

RUN /usr/local/openresty/bin/opm get ledgetech/lua-resty-http
RUN /usr/local/openresty/bin/opm get thibaultcha/lua-resty-jit-uuid

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY handleRequest.lua /srv/
