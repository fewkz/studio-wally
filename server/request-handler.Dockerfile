FROM fabiocicerchia/nginx-lua:latest

COPY nginx.conf /etc/nginx/
COPY handleRequest.lua /srv/

