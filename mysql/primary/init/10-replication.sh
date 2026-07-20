#!/bin/bash
###############################################################################
# Runs ONCE, during the primary's first initialization (empty data directory).
#
# Creates the accounts that the replica and ProxySQL need. Because these run
# after the server has binary logging + GTID enabled, the statements are written
# to the binlog and therefore replicate to the replica automatically.
###############################################################################
set -euo pipefail

SOCKET="/var/lib/mysql/mysql.sock"

ROOT_PW="$(cat /run/secrets/mysql_root_password)"
REPL_PW="$(cat /run/secrets/replication_password)"
APP_PW="$(cat /run/secrets/db_password)"

APP_USER="${MYSQL_USER:-appuser}"
APP_DB="${MYSQL_DATABASE:-appdb}"

# ProxySQL's monitor account password. Must match monitor_password in
# ../proxysql/proxysql.cnf.
MONITOR_PW="monitor123"

mysql --socket="${SOCKET}" -uroot -p"${ROOT_PW}" <<SQL
-- Replication account used by the replica's IO thread.
-- mysql_native_password avoids the caching_sha2 TLS / public-key handshake
-- over the internal Docker network.
CREATE USER IF NOT EXISTS 'replica'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PW}';
GRANT REPLICATION SLAVE ON *.* TO 'replica'@'%';

-- Account ProxySQL uses to monitor server health and the read_only flag.
CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY '${MONITOR_PW}';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';

-- Application user. Switch it to native auth so ProxySQL can authenticate
-- against the backend, and (re)grant it on the app database.
ALTER USER '${APP_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${APP_PW}';
GRANT ALL PRIVILEGES ON \`${APP_DB}\`.* TO '${APP_USER}'@'%';

FLUSH PRIVILEGES;
SQL

echo "[primary-init] replication / monitor / application accounts created."
