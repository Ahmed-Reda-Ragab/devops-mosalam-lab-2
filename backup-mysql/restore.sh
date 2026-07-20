#!/bin/bash

set -Eeuo pipefail

###############################################
# Configuration
###############################################

MYSQL_HOST="${MYSQL_HOST:-mysql-primary}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="$(cat /run/secrets/mysql_root_password)"

BACKUP_ROOT=/backup/backups

###############################################
# Usage
###############################################

usage() {

cat << EOF

Usage:

Restore one database

./restore.sh 2026-07-19 app_db

Restore all databases

./restore.sh 2026-07-19 --all

EOF

exit 1

}

###############################################

[[ $# -lt 2 ]] && usage

DATE="$1"

TARGET="$2"

BACKUP_DIR="$BACKUP_ROOT/$DATE"

###############################################

if [ ! -d "$BACKUP_DIR" ]; then

echo "Backup folder not found."

exit 1

fi

###############################################
# Verify Checksums
###############################################

if [ -f "$BACKUP_DIR/SHA256SUMS" ]; then

echo "Checking Backup Integrity..."

cd "$BACKUP_DIR"

sha256sum -c SHA256SUMS

cd -

fi

###############################################
# Restore One
###############################################

restore_database() {

DB="$1"

FILE="$BACKUP_DIR/$DB.sql.gz"

if [ ! -f "$FILE" ]; then

echo "Backup file not found : $FILE"

exit 1

fi

echo ""

echo "Restoring $DB"

mysql \

-h"$MYSQL_HOST" \

-P"$MYSQL_PORT" \

-u"$MYSQL_USER" \

-p"$MYSQL_PASSWORD" \

-e "CREATE DATABASE IF NOT EXISTS \`$DB\`;"

gunzip -c "$FILE" | mysql \

-h"$MYSQL_HOST" \

-P"$MYSQL_PORT" \

-u"$MYSQL_USER" \

-p"$MYSQL_PASSWORD" \

"$DB"

echo "Done."

}

###############################################

if [ "$TARGET" == "--all" ]; then

for FILE in "$BACKUP_DIR"/*.sql.gz
do

DB=$(basename "$FILE" .sql.gz)

restore_database "$DB"

done

else

restore_database "$TARGET"

fi

echo ""

echo "Restore Completed Successfully."