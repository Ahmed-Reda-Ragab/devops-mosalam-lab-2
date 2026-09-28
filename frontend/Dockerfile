FROM nginx:1.27.2-alpine

COPY index.html /usr/share/nginx/html/
COPY style.css /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN addgroup -S -g 10001 app \
	&& adduser -S -D -H -u 10001 -G app app \
	&& chown -R 10001:10001 /usr/share/nginx/html /var/cache/nginx

USER 10001:10001

EXPOSE 8080

ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off; pid /tmp/nginx.pid;"]
