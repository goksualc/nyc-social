#!/usr/bin/env bash
# Race test: N pending requests, capacity 1, N concurrent host approvals → exactly one may succeed.
set -euo pipefail
NAME=${NAME:-along-pg-test}
N=8
p() { docker exec -i "$NAME" psql -U postgres -d along -v ON_ERROR_STOP=1 -q -t -A "$@"; }

HOST=f0000000-0000-0000-0000-0000000000f0
p <<SQL
select t.root();
insert into auth.users (id, email) values ('$HOST', 'racehost@test');
$(for i in $(seq 1 $N); do echo "insert into auth.users (id, email) values ('f1000000-0000-0000-0000-00000000000$i', 'racer$i@test');"; done)
do \$\$ declare u record; begin
  for u in select id from auth.users where id::text like 'f%' loop
    perform t.login(u.id);
    perform public.complete_profile('Racer', '', '{}', '{}', true);
  end loop; perform t.root(); end \$\$;
SQL

ACT=$(p <<SQL
select t.login('$HOST');
select public.create_cowork('Race plan','',now()+interval '1 hour',now()+interval '2 hours',1,'public','social','Race Cafe','',-73.99,40.74);
SQL
)
ACT=$(echo "$ACT" | tail -1)
REQS=()
for i in $(seq 1 $N); do
  R=$(p <<SQL | tail -1
select t.login('f1000000-0000-0000-0000-00000000000$i');
select public.request_to_join('$ACT');
SQL
)
  REQS+=("$R")
done

OUT=$(mktemp -d)
for i in $(seq 0 $((N-1))); do
  ( p -c "select t.login('$HOST'); select public.respond_to_join_request('${REQS[$i]}', true);" >"$OUT/$i.ok" 2>"$OUT/$i.err" || true ) &
done
wait

ACCEPTED=$(p -c "select count(*) from public.join_requests where activity_id='$ACT' and status='accepted'")
OKS=$(grep -l accepted "$OUT"/*.ok 2>/dev/null | wc -l | tr -d ' ')
FULL=$(grep -l activity_full "$OUT"/*.err 2>/dev/null | wc -l | tr -d ' ')
CONVS=$(p -c "select count(*) from public.conversations where activity_id='$ACT'")
echo "concurrent approvals: attempts=$N succeeded=$OKS rejected_full=$FULL accepted_rows=$ACCEPTED conversations=$CONVS"
if [ "$ACCEPTED" = "1" ] && [ "$OKS" = "1" ] && [ "$CONVS" = "1" ]; then echo "PASS concurrency: capacity never exceeded"; else echo "FAIL concurrency"; exit 1; fi
