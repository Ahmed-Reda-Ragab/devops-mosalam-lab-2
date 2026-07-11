#!/usr/bin/env bash
#
# MySQL logical backup for the running compose stack.
# Writes a compressed, consistent dump to ./backups/ and prunes old ones.
#
# Usage:   ./scripts/backup.sh
# Cron:    0 2 * * *  cd /opt/tms && ./scripts/backup.sh >> /var/log/tms-backup.log 2>&1
#
set -euo pipefail

# --- config (override via env) ---
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DB_NAME="${DB_NAME:-appdb}"
DB_SERVICE="${DB_SERVICE:-db}"
ROOT_PW_FILE="${ROOT_PW_FILE:-./secrets/mysql_root_password}"

cd "$(dirname "$0")/.."

[ -f "$ROOT_PW_FILE" ] || { echo "ERROR: secret file not found: $ROOT_PW_FILE" >&2; exit 1; }
ROOT_PW="$(cat "$ROOT_PW_FILE")"

mkdir -p "$BACKUP_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
FILE="$BACKUP_DIR/${DB_NAME}-${TS}.sql.gz"

echo "[$(date -Is)] backing up '$DB_NAME' -> $FILE"

# --single-transaction => consistent snapshot of InnoDB without locking writers.
# MYSQL_PWD keeps the password out of the process list (argv).
docker compose exec -T -e MYSQL_PWD="$ROOT_PW" "$DB_SERVICE" \
  mysqldump -uroot \
    --single-transaction \
    --routines --triggers --events \
    --databases "$DB_NAME" \
  | gzip -c > "$FILE"

# Fail loudly if the dump is empty or truncated.
if [ ! -s "$FILE" ]; then
  echo "ERROR: backup file is empty — removing $FILE" >&2
  rm -f "$FILE"
  exit 1
fi

SIZE="$(du -h "$FILE" | cut -f1)"
echo "[$(date -Is)] OK ($SIZE)"

# Retention: delete dumps older than RETENTION_DAYS.
DELETED="$(find "$BACKUP_DIR" -name "${DB_NAME}-*.sql.gz" -type f -mtime "+${RETENTION_DAYS}" -print -delete | wc -l | tr -d ' ')"
echo "[$(date -Is)] pruned ${DELETED} backup(s) older than ${RETENTION_DAYS} day(s)"
