#!/usr/bin/env bash
# End-to-end check of the iOS service layer against a real PostgREST + PostGIS built from the migrations.
# Spins up (Docker): Postgres/PostGIS, PostgREST, plus a tiny node proxy; mints JWTs for three users; runs the
# env-gated XCTest `LiveBackendIntegrationTests` on the iOS Simulator. Realtime and Storage are NOT covered.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
PG=along-it-pg; REST=along-it-rest; NET=along-it-net
SECRET="along-integration-test-secret-0123456789abcdef"
PROXY_PORT=${PROXY_PORT:-54321}
DEST=${DEST:-"platform=iOS Simulator,name=iPhone 16 Pro"}
cleanup() { docker rm -f $PG $REST >/dev/null 2>&1 || true; docker network rm $NET >/dev/null 2>&1 || true; [ -n "${PROXY_PID:-}" ] && kill $PROXY_PID 2>/dev/null || true; }
trap cleanup EXIT; cleanup
docker network create $NET >/dev/null
docker run -d --name $PG --network $NET -e POSTGRES_PASSWORD=postgres postgis/postgis:16-3.4 >/dev/null
for i in $(seq 1 90); do docker logs $PG 2>&1 | grep -q "init process complete" && docker exec $PG pg_isready -U postgres >/dev/null 2>&1 && { sleep 1; break; }; sleep 1; done
sql() { docker exec -i $PG psql -U postgres -d along -v ON_ERROR_STOP=1 -q "$@"; }
docker exec $PG psql -U postgres -q -c "create database along" >/dev/null
sql < 00_supabase_stubs.sql; for f in ../migrations/*.sql; do sql < "$f"; done

A=a1111111-1111-1111-1111-111111111111; B=b2222222-2222-2222-2222-222222222222; C=c3333333-3333-3333-3333-333333333333
sql -c "insert into auth.users (id,email,raw_user_meta_data) values ('$A','ada@it','{\"full_name\":\"Ada Lovelace\"}'),('$B','bea@it','{}'),('$C','cy@it','{}');"

docker run -d --name $REST --network $NET -p 3000:3000 \
  -e PGRST_DB_URI="postgres://authenticator:authpw@$PG:5432/along" -e PGRST_DB_SCHEMAS=public \
  -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET="$SECRET" -e PGRST_DB_EXTRA_SEARCH_PATH="public,extensions" postgrest/postgrest >/dev/null
for i in $(seq 1 60); do curl -sf http://127.0.0.1:3000/ >/dev/null 2>&1 && break; sleep 1; done
PROXY_PORT=$PROXY_PORT node proxy.js & PROXY_PID=$!
sleep 1

jwt() { python3 -I - "$SECRET" "$1" <<'PY'
import sys, json, hmac, hashlib, base64, time
secret, sub = sys.argv[1], sys.argv[2]
b = lambda d: base64.urlsafe_b64encode(d).rstrip(b'=').decode()
h = b(json.dumps({"alg":"HS256","typ":"JWT"}).encode()); p = b(json.dumps({"sub":sub,"role":"authenticated","aud":"authenticated","exp":int(time.time())+3600}).encode())
print(f"{h}.{p}.{b(hmac.new(secret.encode(), f'{h}.{p}'.encode(), hashlib.sha256).digest())}")
PY
}

if [ "${UP_ONLY:-}" = "1" ]; then
  echo "A=$A"; echo "JWT_A=$(jwt $A)"; echo "stack is up on :3000 (PostgREST) — press Ctrl-C to stop"; trap cleanup EXIT; wait $PROXY_PID
fi
cd "$ROOT"
export TEST_RUNNER_ALONG_IT_URL="http://127.0.0.1:$PROXY_PORT"
export TEST_RUNNER_ALONG_IT_USER_A=$A TEST_RUNNER_ALONG_IT_USER_B=$B TEST_RUNNER_ALONG_IT_USER_C=$C
export TEST_RUNNER_ALONG_IT_JWT_A=$(jwt $A) TEST_RUNNER_ALONG_IT_JWT_B=$(jwt $B) TEST_RUNNER_ALONG_IT_JWT_C=$(jwt $C)
xcodebuild test -project Along.xcodeproj -scheme Along -destination "$DEST" -only-testing:AlongTests/LiveBackendIntegrationTests \
  CODE_SIGNING_ALLOWED=NO ${XCODE_EXTRA:-} 2>&1 | grep -E "error:|Test Case|Executed|XCTAssert|failed|\*\* TEST" || true
