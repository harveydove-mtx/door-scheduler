#!/usr/bin/env bash
# Build the V2 database from scratch on a throwaway local Postgres and run the SQL tests.
# No Firebase, no network. Needs Postgres 15+ client/server binaries on this machine.
#
#   db/test.sh                 # temp cluster, deleted afterwards
#   DATABASE_URL=... db/test.sh  # use an existing EMPTY database instead
set -euo pipefail
DB_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DB_DIR"

cleanup() { :; }
if [ -z "${DATABASE_URL:-}" ]; then
  PGBIN="$(pg_config --bindir 2>/dev/null || true)"
  [ -x "$PGBIN/initdb" ] || PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
  [ -x "$PGBIN/initdb" ] || { echo "Postgres server binaries not found (initdb)"; exit 1; }
  TMP="$(mktemp -d)"
  AS=()
  if [ "$(id -u)" = 0 ]; then AS=(runuser -u postgres --); chown postgres "$TMP"; fi
  PORT="${PGTEST_PORT:-54329}"
  "${AS[@]}" "$PGBIN/initdb" -D "$TMP/data" -U postgres -A trust --locale=C.UTF-8 -E UTF8 >/dev/null
  "${AS[@]}" "$PGBIN/pg_ctl" -D "$TMP/data" -l "$TMP/log" -w \
    -o "-p $PORT -k $TMP -c listen_addresses='' -c timezone=Europe/London" start >/dev/null
  cleanup() { "${AS[@]}" "$PGBIN/pg_ctl" -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
  trap cleanup EXIT
  DATABASE_URL="postgresql://postgres@/postgres?host=$TMP&port=$PORT"
fi

PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)

echo "== migrations + seed (db/migrate.sh, same as deploys)"
DATABASE_URL="$DATABASE_URL" ./migrate.sh
echo "== migrate.sh again: must apply nothing"
DATABASE_URL="$DATABASE_URL" ./migrate.sh | grep -q "(0 migration(s) applied)" || { echo "   FAIL: second run applied migrations"; exit 1; }
echo "== pricing-engine rate fixture matches seed"
FIXTURE=../app/src/domain/fixtures/seedRateBook.json
if ! diff -q <("${PSQL[@]}" -A -t -f export_ratebook.sql) "$FIXTURE" >/dev/null; then
  echo "   FAIL: $FIXTURE is out of date. Regenerate it with:"
  echo "   psql \$DATABASE_URL -X -A -t -f db/export_ratebook.sql > app/src/domain/fixtures/seedRateBook.json"
  exit 1
fi
echo "== sample data"
"${PSQL[@]}" -f sample_data.sql

echo "== tests"
# PREPARE every query file under its name (generated ones too) for the tests to EXECUTE
PREP="$(mktemp)"; trap 'rm -f "$PREP"; cleanup' EXIT
for q in queries/*.sql queries/generated/*.sql; do
  printf '\\set q `cat %s`\nPREPARE %s AS :q\n;\n' "$q" "$(basename "$q" .sql)" >> "$PREP"
done
pass=0; fail=0
for f in tests/[0-9]*.sql; do
  if out="$("${PSQL[@]}" -f tests/_helpers.sql -f "$PREP" -f "$f" 2>&1)"; then
    n="$(grep -c 'ok - ' <<<"$out" || true)"; pass=$((pass + n))
    echo "   PASS $f ($n checks)"
  else
    fail=$((fail + 1))
    echo "   FAIL $f"; sed 's/^/        /' <<<"$out" | grep -v -e "NOTICE:  ok - " -e "skipping" | tail -15
  fi
done
echo "== $pass checks passed, $fail file(s) failed"
[ "$fail" = 0 ]
