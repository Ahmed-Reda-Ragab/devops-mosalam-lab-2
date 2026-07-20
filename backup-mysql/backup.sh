#!/bin/bash

set -euo pipefail

##########################################
# Config
##########################################

MYSQL_HOST="${MYSQL_HOST:-mysql-primary}"

MYSQL_PORT="${MYSQL_PORT:-3306}"

MYSQL_USER="${MYSQL_USER:-root}"

MYSQL_PASSWORD="$(cat /run/secrets/mysql_root_password)"

BACKUP_ROOT=/backup/backups

TODAY=$(date +%F)

BACKUP_DIR=$BACKUP_ROOT/$TODAY

mkdir -p "$BACKUP_DIR"

echo "=================================="

echo "Backup Started : $(date)"

echo "=================================="

##########################################
# Get Databases
##########################################

DATABASES=$(mysql \
-h"$MYSQL_HOST" \
-P"$MYSQL_PORT" \
-u"$MYSQL_USER" \
-p"$MYSQL_PASSWORD" \
-N \
-e "SHOW DATABASES;" \
| grep -Ev "(information_schema|performance_schema|mysql|sys)")

##########################################
# Backup Loop
##########################################

for DB in $DATABASES
do

echo ""

echo "Backing up : $DB"

mysqldump \

-h"$MYSQL_HOST" \

-P"$MYSQL_PORT" \

-u"$MYSQL_USER" \

-p"$MYSQL_PASSWORD" \

--single-transaction \

--quick \

--routines \

--events \

--triggers \

"$DB" \

| gzip > "$BACKUP_DIR/$DB.sql.gz"

sha256sum "$BACKUP_DIR/$DB.sql.gz" >> "$BACKUP_DIR/SHA256SUMS"
echo "Done : $DB"

done

echo ""

echo "Finished : $(date)"