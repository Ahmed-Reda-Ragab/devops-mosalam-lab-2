#!/bin/sh
###############################################################################
# ProxySQL entrypoint.
#  1. Start ProxySQL (fresh config from /etc/proxysql.cnf).
#  2. Wait for the admin interface (6032) to come up.
#  3. Load servers / query rules from /etc/proxysql-init.sql.
#  4. Create the application frontend user from the mounted db_password secret,
#     so it always matches the MySQL 'appuser' password (which is a secret and
#     therefore cannot be hard-coded in a static .sql/.cnf file).
###############################################################################
set -e

# 1) Launch ProxySQL in the foreground, in the background of this script.
proxysql --initial -f -c /etc/proxysql.cnf &
PROXYSQL_PID=$!

# 2) Wait for the admin interface.
echo "[proxysql] waiting for admin interface on 6032..."
until mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT 1" >/dev/null 2>&1; do
  sleep 2
done

# 3) Load backend servers, replication hostgroups and query rules.
echo "[proxysql] loading servers / query rules..."
mysql -h127.0.0.1 -P6032 -uadmin -padmin < /etc/proxysql-init.sql

# 4) (Re)create the application user from the secret.
APP_USER="${DB_USERNAME:-appuser}"
APP_PW="$(cat /run/secrets/db_password)"

echo "[proxysql] configuring application user '${APP_USER}'..."
mysql -h127.0.0.1 -P6032 -uadmin -padmin <<SQL
DELETE FROM mysql_users WHERE username='${APP_USER}';
INSERT INTO mysql_users (username, password, default_hostgroup, active, transaction_persistent)
VALUES ('${APP_USER}', '${APP_PW}', 10, 1, 1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
SQL

echo "[proxysql] ready. Apps connect on :6033, admin on :6032."

# Keep the container alive on the ProxySQL process.
wait "$PROXYSQL_PID"
