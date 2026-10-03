FROM nginx:1.27.2-alpine

COPY index.html /usr/share/nginx/html/
COPY style.css /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/
# Replaces the MAIN config (not a conf.d snippet): pid and temp paths live in
# /tmp so nginx runs as non-root on a read-only root filesystem.
COPY nginx.conf /etc/nginx/nginx.conf

RUN addgroup -S -g 1001 app \
	&& adduser -S -D -H -u 1001 -G app app \
	&& chown -R 1001:1001 /usr/share/nginx/html /var/cache/nginx

USER 1001:1001

EXPOSE 8080

ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
