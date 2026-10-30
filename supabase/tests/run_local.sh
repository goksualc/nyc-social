#!/usr/bin/env bash
# Runs every migration + the SQL test-suite against a throwaway PostGIS container (needs Docker).
# Usage: supabase/tests/run_local.sh        (exit code != 0 when any test fails)
set -euo pipefail
cd "$(dirname "$0")"
NAME=along-pg-test
PORT=${PORT:-54399}
docker rm -f $NAME >/dev/null 2>&1 || true
docker run -d --name $NAME -e POSTGRES_PASSWORD=postgres -p $PORT:5432 postgis/postgis:16-3.4 >/dev/null
trap 'docker rm -f $NAME >/dev/null 2>&1 || true' EXIT
psql_() { docker exec -i $NAME psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
# The image restarts Postgres once after init; wait for the final "ready" line.
for i in $(seq 1 90); do
  if docker logs $NAME 2>&1 | grep -q "init process complete" && docker exec $NAME pg_isready -U postgres >/dev/null 2>&1; then sleep 1; break; fi
  sleep 1
done
psql_ -c "create database along" >/dev/null
psql_() { docker exec -i $NAME psql -U postgres -d along -v ON_ERROR_STOP=1 -q "$@"; }
psql_ -c "create extension if not exists postgis;" >/dev/null 2>&1 || true   # harness only; migration installs it into `extensions`
psql_ -c "drop extension postgis cascade;" >/dev/null 2>&1 || true
echo "== stubs";      psql_ < 00_supabase_stubs.sql
for f in ../migrations/*.sql; do echo "== migrate $(basename "$f")"; psql_ < "$f"; done
echo "== helpers";    psql_ < 01_helpers.sql
echo "== tests";      psql_ < 10_rls_and_rpc_tests.sql > /tmp/along_sql_results.txt 2>&1 || { cat /tmp/along_sql_results.txt; exit 1; }
cat /tmp/along_sql_results.txt | grep -E "FAIL|passed|failed|^ *[0-9]+ \|" | head -80
echo "== concurrency"; PORT=$PORT NAME=$NAME bash ./20_concurrency.sh
