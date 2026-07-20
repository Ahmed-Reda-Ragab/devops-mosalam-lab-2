FROM proxysql/proxysql:2.7

LABEL maintainer="El Programmer"

# The base ProxySQL image does not ship a MySQL client, but startup.sh needs one
# to talk to the ProxySQL admin interface (port 6032) and load configuration.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client \
    && rm -rf /var/lib/apt/lists/*
