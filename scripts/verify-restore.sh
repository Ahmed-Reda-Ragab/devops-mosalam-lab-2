#!/usr/bin/env bash
#
# DR drill: prove the latest backup is actually restorable.
# Restores it into a THROWAWAY MySQL container (never touches the live DB) and
# asserts the data came back. Run this on a schedule — an untested backup is
# not a backup.
#
# Usage:   ./scripts/verify-restore.sh
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
DB_NAME="${DB_NAME:-appdb}"
CHECK_TABLE="${CHECK_TABLE:-tasks}"
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.0}"

cd "$(dirname "$0")/.."

FILE="$(ls -1t "${BACKUP_DIR}"/${DB_NAME}-*.sql.gz 2>/dev/null | head -1 || true)"
[ -n "$FILE" ] || { echo "ERROR: no backup found in ${BACKUP_DIR}" >&2; exit 1; }
echo "[$(date -Is)] DR drill using: $FILE"

NAME="tms-dr-test-$$"
TEST_PW="drtest"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$NAME" -e MYSQL_ROOT_PASSWORD="$TEST_PW" "$MYSQL_IMAGE" >/dev/null

echo -n "[$(date -Is)] waiting for throwaway mysql to be ready"
for _ in $(seq 1 60); do
  if docker exec -e MYSQL_PWD="$TEST_PW" "$NAME" mysqladmin ping -uroot --silent >/dev/null 2>&1; then
    ready=1; break
  fi
  echo -n "."; sleep 2
done
echo
[ "${ready:-0}" = "1" ] || { echo "ERROR: mysql did not become ready" >&2; exit 1; }

echo "[$(date -Is)] importing backup..."
gunzip -c "$FILE" | docker exec -i -e MYSQL_PWD="$TEST_PW" "$NAME" mysql -uroot

ROWS="$(docker exec -e MYSQL_PWD="$TEST_PW" "$NAME" \
  mysql -uroot -N -B -e "SELECT COUNT(*) FROM \`${DB_NAME}\`.\`${CHECK_TABLE}\`;" 2>/dev/null || echo ERR)"

if [ "$ROWS" = "ERR" ] || [ -z "$ROWS" ]; then
  echo "❌ DR drill FAILED — could not read ${DB_NAME}.${CHECK_TABLE} from the restore"
  exit 1
fi

echo "✅ DR drill PASSED — ${DB_NAME}.${CHECK_TABLE} restored with ${ROWS} row(s)"
