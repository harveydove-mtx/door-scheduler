#!/usr/bin/env bash
# End-to-end test of the Data Connect connector against a real Postgres set up like Cloud SQL:
#   1. throwaway Postgres + the Cloud SQL / Data Connect roles (cloudsql_roles.sql)
#   2. db/migrate.sh as the owner role, exactly as the deploy workflow does, + sample data
#   3. the Data Connect emulator, connected as a WRITER-only login (like production)
#   4. operations.test.mjs calls every operation over HTTP with signed-in test users
# Needs: Postgres 15+ binaries, Node 20+, and the emulator binary
# (firebase setup:emulators:dataconnect downloads it to ~/.cache/firebase/emulators).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
PGBIN="$(pg_config --bindir 2>/dev/null || true)"
[ -x "$PGBIN/initdb" ] || PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
EMU="${DATACONNECT_EMULATOR_BINARY:-$(ls -t "$HOME"/.cache/firebase/emulators/dataconnect-emulator-* 2>/dev/null | head -1)}"
[ -x "$EMU" ] || { echo "Data Connect emulator not found: run 'npx firebase-tools setup:emulators:dataconnect'"; exit 1; }
PGPORT="${PGTEST_PORT:-54331}"; FDCPORT="${FDC_TEST_PORT:-9398}"

TMP="$(mktemp -d)"; AS=()
if [ "$(id -u)" = 0 ]; then AS=(runuser -u postgres --); chown postgres "$TMP"; fi
EMU_PID=""
cleanup() {
  [ -n "$EMU_PID" ] && kill "$EMU_PID" 2>/dev/null || true
  "${AS[@]}" "$PGBIN/pg_ctl" -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true
  [ "${KEEP_LOGS:-}" = 1 ] && echo "logs kept in $TMP" || rm -rf "$TMP"
}
trap cleanup EXIT

echo "== postgres + Cloud SQL-style roles"
"${AS[@]}" "$PGBIN/initdb" -D "$TMP/data" -U postgres -A trust --locale=C.UTF-8 -E UTF8 >/dev/null
"${AS[@]}" "$PGBIN/pg_ctl" -D "$TMP/data" -l "$TMP/pg.log" -w \
  -o "-p $PGPORT -k $TMP -c listen_addresses=127.0.0.1 -c timezone=Europe/London" start >/dev/null
SU="postgresql://postgres@127.0.0.1:$PGPORT"
psql "$SU/postgres" -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE doorscheduler"
psql "$SU/doorscheduler" -X -q -v ON_ERROR_STOP=1 -f "$HERE/cloudsql_roles.sql"

echo "== migrations as the owner role (like the deploy workflow)"
MIG="postgresql://migrator@127.0.0.1:$PGPORT/doorscheduler"
psql "$MIG" -X -q -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
DATABASE_URL="$MIG" MIGRATE_ROLE=firebaseowner_doorscheduler_public "$ROOT/db/migrate.sh"
psql "$MIG" -X -q -v ON_ERROR_STOP=1 -c "SET ROLE firebaseowner_doorscheduler_public" -f "$ROOT/db/sample_data.sql"
owners="$(psql "$SU/doorscheduler" -X -A -t -c "SELECT string_agg(DISTINCT tableowner, ',') FROM pg_tables WHERE schemaname = 'public'")"
[ "$owners" = "firebaseowner_doorscheduler_public" ] || { echo "FAIL: tables owned by $owners"; exit 1; }
echo "   all tables owned by firebaseowner_doorscheduler_public"

echo "== Data Connect emulator (connected as the writer-only role)"
"$EMU" --logtostderr -v=2 dev -listen="127.0.0.1:$FDCPORT" -config_dir="$ROOT/dataconnect" \
  -local_connection_string="postgresql://fdc_service@127.0.0.1:$PGPORT/doorscheduler?sslmode=disable" \
  > "$TMP/emulator.log" 2>&1 &
EMU_PID=$!
for _ in $(seq 1 60); do curl -s -o /dev/null "http://127.0.0.1:$FDCPORT" && break; sleep 1; done
if grep -q "Running migration SQL" "$TMP/emulator.log"; then
  echo "FAIL: the emulator tried to change the database schema:"; grep -A3 "Running migration SQL" "$TMP/emulator.log"; exit 1
fi
grep -qiE "error.*(connector|schema)" "$TMP/emulator.log" && { echo "FAIL: emulator reported errors"; tail -20 "$TMP/emulator.log"; exit 1; }

echo "== operations"
FDC_URL="http://127.0.0.1:$FDCPORT" DATABASE_URL="$SU/doorscheduler" node "$HERE/operations.test.mjs"
