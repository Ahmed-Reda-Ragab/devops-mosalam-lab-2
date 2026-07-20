#!/bin/bash
###############################################################################
# Runs ONCE, during the replica's first initialization.
#
# Points the replica at the primary using GTID auto-positioning and starts
# replication. The configuration is stored in the replica's data dir
# (mysql.slave_master_info), so replication resumes automatically on every
# subsequent restart.
###############################################################################
set -euo pipefail

SOCKET="/var/lib/mysql/mysql.sock"

ROOT_PW="$(cat /run/secrets/mysql_root_password)"
REPL_PW="$(cat /run/secrets/replication_password)"

PRIMARY_HOST="mysql-primary"
PRIMARY_PORT="3306"

# Wait until the primary is up AND the replication account actually works.
echo "[replica-init] waiting for ${PRIMARY_HOST} replication account..."
until mysql -h"${PRIMARY_HOST}" -P"${PRIMARY_PORT}" -ureplica -p"${REPL_PW}" -e "SELECT 1" >/dev/null 2>&1; do
  sleep 3
done

mysql --socket="${SOCKET}" -uroot -p"${ROOT_PW}" <<SQL
STOP REPLICA;

-- Clear any GTIDs generated locally while this replica's data dir was
-- initialized, so GTID auto-positioning pulls a clean history from the primary
-- and we avoid "errant transactions".
RESET MASTER;

CHANGE REPLICATION SOURCE TO
  SOURCE_HOST          = '${PRIMARY_HOST}',
  SOURCE_PORT          = ${PRIMARY_PORT},
  SOURCE_USER          = 'replica',
  SOURCE_PASSWORD      = '${REPL_PW}',
  SOURCE_AUTO_POSITION = 1;

START REPLICA;

-- Full read-only protection, persisted so it survives restarts.
-- (Replication threads bypass this, so replication keeps working.)
SET PERSIST super_read_only = ON;
SQL

echo "[replica-init] replication started against ${PRIMARY_HOST}."
