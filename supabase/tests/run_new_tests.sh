#!/usr/bin/env bash
# Runs ALL migrations against a throwaway PostGIS container (needs Docker), then the SQL tests for the newer features:
#   30 anonymous organizers + messaging before acceptance      40 route search
# (10_rls_and_rpc_tests.sql predates the walk-only pivot and still calls the retired create_cowork.)
# Usage: supabase/tests/run_new_tests.sh   — exit code != 0 when any check fails.
set -euo pipefail
cd "$(dirname "$0")"
NAME=along-pg-test2
PORT=${PORT:-54398}
docker rm -f $NAME >/dev/null 2>&1 || true
docker run -d --name $NAME -e POSTGRES_PASSWORD=postgres -p $PORT:5432 postgis/postgis:16-3.4 >/dev/null
trap 'docker rm -f $NAME >/dev/null 2>&1 || true' EXIT
for i in $(seq 1 90); do
  if docker logs $NAME 2>&1 | grep -q "init process complete" && docker exec $NAME pg_isready -U postgres >/dev/null 2>&1; then sleep 1; break; fi
  sleep 1
done
docker exec -i $NAME psql -U postgres -q -c "create database along" >/dev/null
psql_() { docker exec -i $NAME psql -U postgres -d along -v ON_ERROR_STOP=1 -q "$@"; }
psql_ -c "create extension if not exists postgis;" >/dev/null 2>&1 || true
psql_ -c "drop extension postgis cascade;" >/dev/null 2>&1 || true
echo "== stubs";   psql_ < 00_supabase_stubs.sql
for f in ../migrations/*.sql; do echo "== migrate $(basename "$f")"; psql_ < "$f"; done
echo "== helpers"; psql_ < 01_helpers.sql
# Every test file runs in its own copy of the migrated database, so one file's data never leaks into another's results.
for t in ${TESTS:-30_anonymous_and_request_chat_tests.sql 40_route_search_tests.sql}; do
  [ -f "$t" ] || continue
  echo "== $t"
  db="t_$(basename "$t" .sql)"
  docker exec -i $NAME psql -U postgres -q -c "create database $db template along" >/dev/null
  run() { docker exec -i $NAME psql -U postgres -d "$db" -v ON_ERROR_STOP=1 -q "$@"; }
  if [ -n "${ECHO:-}" ]; then run -a < "$t" 2>&1 | tail -25; continue; fi
  run < "$t" 2>&1 | grep -v "^ *$" | grep -E "FAIL|ERROR|CONTEXT|passed|failed|^ *[0-9]+ *\\|" | head -60
done
