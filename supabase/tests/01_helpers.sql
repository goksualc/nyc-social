-- test helpers (superuser-owned, schema `t`)
create schema t;
create function t.login(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  perform set_config('role', 'authenticated', false);
end $$;
create function t.anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('role', 'anon', false);
end $$;
create function t.root() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', false);
  perform set_config('request.jwt.claim.sub', '', false);
end $$;
grant usage on schema t to anon, authenticated;
grant execute on all functions in schema t to anon, authenticated;

create table t.log (n serial, name text, ok boolean, detail text);
create function t.check(p_name text, p_cond boolean, p_detail text default '') returns void language plpgsql as $$
begin
  insert into t.log (name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail);
end $$;

-- Runs `p_sql` and records PASS only if it raises an error containing `p_expect`.
create function t.expect_error(p_name text, p_sql text, p_expect text) returns void language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
    insert into t.log (name, ok, detail) values (p_name, false, 'no error raised');
  exception when others then
    v_msg := sqlerrm;
    insert into t.log (name, ok, detail) values (p_name, position(p_expect in v_msg) > 0, v_msg);
  end;
end $$;

-- Runs `p_sql` and returns its single integer result.
create function t.scalar(p_sql text) returns bigint language plpgsql as $$
declare v bigint;
begin execute p_sql into v; return v; end $$;
grant all on t.log to anon, authenticated;
grant usage on sequence t.log_n_seq to anon, authenticated;
