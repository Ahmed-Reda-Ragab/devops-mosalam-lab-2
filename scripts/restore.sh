#!/usr/bin/env bash
#
# Restore a MySQL backup into the LIVE database of the running compose stack.
# This overwrites current data — it will ask for confirmation first.
#
# Usage:   ./scripts/restore.sh backups/appdb-20260707-020000.sql.gz
#
set -euo pipefail

FILE="${1:?Usage: $0 <backup-file.sql.gz>}"
DB_NAME="${DB_NAME:-appdb}"
DB_SERVICE="${DB_SERVICE:-db}"
ROOT_PW_FILE="${ROOT_PW_FILE:-./secrets/mysql_root_password}"

cd "$(dirname "$0")/.."

[ -f "$FILE" ]         || { echo "ERROR: backup not found: $FILE" >&2; exit 1; }
[ -f "$ROOT_PW_FILE" ] || { echo "ERROR: secret file not found: $ROOT_PW_FILE" >&2; exit 1; }
ROOT_PW="$(cat "$ROOT_PW_FILE")"

echo "!! This will OVERWRITE database '$DB_NAME' on service '$DB_SERVICE' with:"
echo "   $FILE"
read -r -p "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "aborted."; exit 1; }

# The dump was taken with --databases, so it recreates the schema on import.
gunzip -c "$FILE" | docker compose exec -T -e MYSQL_PWD="$ROOT_PW" "$DB_SERVICE" mysql -uroot

echo "[$(date -Is)] restore complete."
