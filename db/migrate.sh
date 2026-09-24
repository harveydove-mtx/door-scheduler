#!/usr/bin/env bash
# Bring a V2 database up to date: apply each db/migrations/*.sql ONCE, in order, and load
# seed.sql the first time only. Safe to run on every deploy.
#
#   DATABASE_URL=postgres://... db/migrate.sh
#   MIGRATE_ROLE=<role>   optional: run as this role (SET ROLE) so the tables it creates are
#                         owned by it; on Cloud SQL this is the Data Connect owner role.
#   SKIP_SEED=1           optional: never load seed.sql
#
# Applied files are recorded in schema_migrations with a checksum. If an already-applied
# migration file has been edited, this stops: add a NEW migration instead of editing one.
set -euo pipefail
DB_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${DATABASE_URL:?set DATABASE_URL}"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)
ROLE_SQL=()
if [ -n "${MIGRATE_ROLE:-}" ]; then ROLE_SQL=(-c "SET ROLE \"${MIGRATE_ROLE}\""); fi
sum() { sha256sum "$1" | cut -d' ' -f1; }

"${PSQL[@]}" "${ROLE_SQL[@]}" -c "
  CREATE TABLE IF NOT EXISTS schema_migrations (
    filename   text PRIMARY KEY,
    checksum   text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
  )"

fresh="$("${PSQL[@]}" -A -t -c "SELECT count(*) = 0 FROM schema_migrations")"
applied=0
for f in "$DB_DIR"/migrations/*.sql; do
  name="$(basename "$f")"; c="$(sum "$f")"
  have="$("${PSQL[@]}" -A -t -c "SELECT checksum FROM schema_migrations WHERE filename = '$name'")"
  if [ -n "$have" ]; then
    [ "$have" = "$c" ] || { echo "ERROR: $name was changed after it was applied. Add a new migration instead."; exit 1; }
    continue
  fi
  echo "   applying $name"
  "${PSQL[@]}" -1 "${ROLE_SQL[@]}" -f "$f" \
    -c "INSERT INTO schema_migrations (filename, checksum) VALUES ('$name', '$c')"
  applied=$((applied + 1))
done

if [ "$fresh" = "t" ] && [ -z "${SKIP_SEED:-}" ]; then
  echo "   loading seed.sql (new database)"
  "${PSQL[@]}" "${ROLE_SQL[@]}" -f "$DB_DIR/seed.sql" \
    -c "INSERT INTO schema_migrations (filename, checksum) VALUES ('seed.sql', '$(sum "$DB_DIR/seed.sql")')"
fi
echo "   database up to date ($applied migration(s) applied)"
