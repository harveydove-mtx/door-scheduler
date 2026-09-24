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

echo "== migrations"
for f in migrations/*.sql; do echo "   $f"; "${PSQL[@]}" -f "$f"; done
echo "== seed"
"${PSQL[@]}" -f seed.sql
echo "== sample data"
"${PSQL[@]}" -f sample_data.sql

echo "== tests"
pass=0; fail=0
for f in tests/[0-9]*.sql; do
  if out="$("${PSQL[@]}" -f tests/_helpers.sql -f "$f" 2>&1)"; then
    n="$(grep -c 'ok - ' <<<"$out" || true)"; pass=$((pass + n))
    echo "   PASS $f ($n checks)"
  else
    fail=$((fail + 1))
    echo "   FAIL $f"; sed 's/^/        /' <<<"$out" | grep -v -e "NOTICE:  ok - " -e "skipping" | tail -15
  fi
done
echo "== $pass checks passed, $fail file(s) failed"
[ "$fail" = 0 ]
