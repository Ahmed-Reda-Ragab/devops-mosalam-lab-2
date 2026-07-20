FROM alpine:3.21

LABEL maintainer="El Programmer"

# Install packages
RUN apk add --no-cache \
        bash \
        mysql-client \
        tzdata \
        gzip \
        coreutils \
        findutils \
        dcron

# Working directory
WORKDIR /backup

# Create directories
RUN mkdir -p \
        /backup/scripts \
        /backup/backups \
        /backup/logs

# Copy scripts
COPY backup.sh /backup/scripts/
COPY cleanup.sh /backup/scripts/
COPY entrypoint.sh /backup/
COPY crontab /etc/crontabs/root

# Permissions
RUN chmod +x \
        /backup/entrypoint.sh \
        /backup/scripts/backup.sh \
        /backup/scripts/cleanup.sh

ENTRYPOINT ["/backup/entrypoint.sh"]