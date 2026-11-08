-- Along · migration 9 — live walk sessions, readiness, completion, walk history, Realtime authorization
--
-- State machine (server-authoritative; every transition happens inside an RPC with server timestamps):
--
--   awaiting_participants → ready_to_start → active → awaiting_completion → completed
--            └───────────────┴──────────────┴──────────────┴─────→ cancelled | ended_early | expired
--
-- Phase 1 is exactly two people: the host and ONE accepted walking buddy. The schema keys participants by
-- (session, user), so group walks can be added later without a redesign. Existing multi-guest plans are untouched;
-- they just can't open a live session until only one guest is accepted.
--
-- Live positions are NEVER stored. They travel over a private Realtime broadcast channel `walk:<session id>`,
-- authorised by the policies on realtime.messages below. Only history-safe summaries (duration, approximate
-- distance) are persisted. Does not modify earlier migrations.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table public.walk_sessions (
  id                  uuid primary key default gen_random_uuid(),
  activity_id         uuid not null references public.activities (id) on delete cascade,
  status              text not null default 'awaiting_participants'
                        check (status in ('awaiting_participants', 'ready_to_start', 'active', 'awaiting_completion',
                                          'completed', 'cancelled', 'ended_early', 'expired')),
  started_at          timestamptz,
  ended_at            timestamptz,
  duration_seconds    integer check (duration_seconds >= 0),
  distance_meters     integer check (distance_meters >= 0),
  completion_deadline timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
-- One open session per activity: duplicate "open" / "start" requests resolve to the same row.
create unique index walk_sessions_one_open_per_activity on public.walk_sessions (activity_id)
  where status in ('awaiting_participants', 'ready_to_start', 'active', 'awaiting_completion');
create index walk_sessions_activity_idx on public.walk_sessions (activity_id, created_at desc);
create trigger walk_sessions_set_updated_at before update on public.walk_sessions
  for each row execute function public.set_updated_at();

create table public.walk_session_participants (
  session_id              uuid not null references public.walk_sessions (id) on delete cascade,
  user_id                 uuid not null references public.profiles (id) on delete cascade,
  role                    text not null check (role in ('host', 'guest')),
  joined_at               timestamptz,
  ready_at                timestamptz,
  completion_confirmed_at timestamptz,
  finished_at             timestamptz,
  sharing_stopped_at      timestamptz,
  reported_distance_m     integer check (reported_distance_m between 0 and 100000),
  -- memory privacy: each participant decides for themselves (private by default)
  show_on_profile         boolean not null default false,
  reveal_partner          boolean not null default false,
  primary key (session_id, user_id)
);
create index walk_session_participants_user_idx on public.walk_session_participants (user_id);

alter table public.walk_sessions             enable row level security;
alter table public.walk_session_participants enable row level security;
revoke all on public.walk_sessions, public.walk_session_participants from anon, authenticated;

create or replace function private.is_session_member(p_session uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.walk_session_participants where session_id = p_session and user_id = auth.uid())
$$;

-- Members read their own sessions (needed for Realtime change events). All writes go through the RPCs below.
create policy walk_sessions_select on public.walk_sessions for select to authenticated
  using (private.is_session_member(id));
create policy walk_session_participants_select on public.walk_session_participants for select to authenticated
  using (private.is_session_member(session_id));
grant select on public.walk_sessions to authenticated;
grant select (session_id, user_id, role, joined_at, ready_at, completion_confirmed_at, finished_at, sharing_stopped_at)
  on public.walk_session_participants to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.walk_sessions, public.walk_session_participants;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Realtime authorization for the live-location channel (`walk:<session id>`)
--    A participant may join/send/receive only while the session is live AND they have not stopped sharing.
--    Stopping sharing (or finishing) therefore revokes channel access server-side, immediately.
-- ---------------------------------------------------------------------------
create or replace function private.can_use_walk_channel(p_topic text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_topic ~ '^walk:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then exists (
      select 1
      from public.walk_sessions s
      join public.walk_session_participants p on p.session_id = s.id
      where s.id = substring(p_topic from 6)::uuid
        and p.user_id = auth.uid()
        and s.status in ('active', 'awaiting_completion')
        and p.sharing_stopped_at is null)
    else false
  end
$$;

do $$
begin
  execute 'drop policy if exists walk_channel_receive on realtime.messages';
  execute 'drop policy if exists walk_channel_send on realtime.messages';
  execute $p$create policy walk_channel_receive on realtime.messages for select to authenticated
             using (realtime.messages.extension = 'broadcast' and private.can_use_walk_channel(realtime.topic()))$p$;
  execute $p$create policy walk_channel_send on realtime.messages for insert to authenticated
             with check (realtime.messages.extension = 'broadcast' and private.can_use_walk_channel(realtime.topic()))$p$;
exception when undefined_table or invalid_schema_name then
  raise notice 'realtime.messages not found: enable "Realtime Authorization" in the Supabase dashboard, then re-run section 2.';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

-- Moves abandoned sessions to a terminal state (documented timeouts; nothing stays "active" forever).
--   awaiting_completion : 24 h after the first confirmation without the second → expired (not counted as a walk)
--   active              : 8 h after the start → expired
--   awaiting_participants / ready_to_start : 6 h after the plan's end time → expired; cancelled plans → cancelled
create or replace function private.expire_walk_sessions()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.walk_sessions set status = 'expired', ended_at = coalesce(ended_at, now())
   where status = 'awaiting_completion' and completion_deadline < now();
  update public.walk_sessions set status = 'expired', ended_at = coalesce(ended_at, now())
   where status = 'active' and started_at < now() - interval '8 hours';
  update public.walk_sessions s set status = 'expired', ended_at = now()
    from public.activities a
   where a.id = s.activity_id and s.status in ('awaiting_participants', 'ready_to_start')
     and a.end_time < now() - interval '6 hours';
  update public.walk_sessions s set status = 'cancelled', ended_at = now()
    from public.activities a
   where a.id = s.activity_id and s.status in ('awaiting_participants', 'ready_to_start', 'active') and a.status <> 'active';
  update public.walk_session_participants p set sharing_stopped_at = coalesce(sharing_stopped_at, now())
    from public.walk_sessions s
   where s.id = p.session_id and s.status not in ('active', 'awaiting_completion') and p.sharing_stopped_at is null;
end $$;

create or replace function private.walk_session_json(p_session uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'activity_id', s.activity_id, 'status', s.status,
    'started_at', s.started_at, 'ended_at', s.ended_at,
    'duration_seconds', s.duration_seconds, 'distance_meters', s.distance_meters,
    'completion_deadline', s.completion_deadline,
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', p.user_id, 'role', p.role, 'display_name', coalesce(pr.display_name, 'Someone'),
               'avatar_path', case when pr.visibility = 'everyone' or p.user_id = auth.uid() then pr.avatar_url end,
               'joined_at', p.joined_at, 'ready_at', p.ready_at,
               'completion_confirmed_at', p.completion_confirmed_at, 'sharing_stopped_at', p.sharing_stopped_at)
             order by p.role desc)
        from public.walk_session_participants p join public.profiles pr on pr.id = p.user_id
       where p.session_id = s.id), '[]'::jsonb))
  from public.walk_sessions s where s.id = p_session
$$;

-- ---------------------------------------------------------------------------
-- 4. State-machine RPCs
-- ---------------------------------------------------------------------------

-- Opens (or returns) the live session for a plan. Idempotent. The caller must be the host or the accepted guest.
create or replace function public.open_walk_session(p_activity_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := private.require_ready();
  v_act public.activities%rowtype;
  v_guests uuid[];
  v_session uuid;
begin
  perform private.expire_walk_sessions();
  select * into v_act from public.activities where id = p_activity_id;
  if not found then raise exception 'not_found'; end if;
  if v_act.status <> 'active' then raise exception 'activity_closed'; end if;
  if private.blocked_with(v_act.creator_id) then raise exception 'not_found'; end if;

  select coalesce(array_agg(requester_id), '{}') into v_guests
    from public.join_requests where activity_id = p_activity_id and status = 'accepted';
  if v_uid <> v_act.creator_id and not (v_uid = any (v_guests)) then raise exception 'not_allowed'; end if;
  if cardinality(v_guests) = 0 then raise exception 'no_participant'; end if;
  if cardinality(v_guests) > 1 then raise exception 'session_requires_two'; end if;

  perform pg_advisory_xact_lock(hashtext(p_activity_id::text));
  select id into v_session from public.walk_sessions
   where activity_id = p_activity_id and status in ('awaiting_participants', 'ready_to_start', 'active', 'awaiting_completion');
  if v_session is null then
    -- a finished session for this plan is final: one plan, one shared walk
    if exists (select 1 from public.walk_sessions where activity_id = p_activity_id and status = 'completed') then
      select id into v_session from public.walk_sessions where activity_id = p_activity_id and status = 'completed' limit 1;
      return private.walk_session_json(v_session);
    end if;
    insert into public.walk_sessions (activity_id) values (p_activity_id) returning id into v_session;
    insert into public.walk_session_participants (session_id, user_id, role)
      values (v_session, v_act.creator_id, 'host'), (v_session, v_guests[1], 'guest');
  end if;
  update public.walk_session_participants set joined_at = coalesce(joined_at, now())
   where session_id = v_session and user_id = v_uid;
  update public.walk_sessions s set status = 'ready_to_start'
   where s.id = v_session and s.status = 'awaiting_participants'
     and not exists (select 1 from public.walk_session_participants where session_id = s.id and joined_at is null);
  return private.walk_session_json(v_session);
end $$;

-- The latest session for a plan, as seen by a member (null when none).
create or replace function public.get_walk_session(p_activity_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  perform private.expire_walk_sessions();
  select s.id into v_id from public.walk_sessions s
   where s.activity_id = p_activity_id and private.is_session_member(s.id)
   order by s.created_at desc limit 1;
  if v_id is null then return null; end if;
  return private.walk_session_json(v_id);
end $$;

-- "I'm Ready". Both people must press it; the second press atomically starts the walk (exactly once).
create or replace function public.set_walk_ready(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := private.require_ready();
  v_s public.walk_sessions%rowtype;
  v_guests integer;
begin
  perform private.expire_walk_sessions();
  select * into v_s from public.walk_sessions where id = p_session_id for update;     -- serialises simultaneous presses
  if not found or not private.is_session_member(p_session_id) then raise exception 'not_found'; end if;
  if v_s.status = 'active' then return private.walk_session_json(p_session_id); end if;   -- duplicate press: no-op
  if v_s.status not in ('awaiting_participants', 'ready_to_start') then raise exception 'session_closed'; end if;

  select count(*) into v_guests from public.join_requests where activity_id = v_s.activity_id and status = 'accepted';
  if v_guests <> 1 then raise exception 'session_requires_two'; end if;

  update public.walk_session_participants
     set joined_at = coalesce(joined_at, now()), ready_at = coalesce(ready_at, now())
   where session_id = p_session_id and user_id = v_uid;

  if not exists (select 1 from public.walk_session_participants where session_id = p_session_id and ready_at is null) then
    update public.walk_sessions set status = 'active', started_at = now() where id = p_session_id;
  elsif not exists (select 1 from public.walk_session_participants where session_id = p_session_id and joined_at is null) then
    update public.walk_sessions set status = 'ready_to_start' where id = p_session_id;
  end if;
  return private.walk_session_json(p_session_id);
end $$;

-- Pause / resume my own location sharing. Takes effect immediately and needs nobody's approval.
-- While off, the Realtime policy denies me the channel in both directions.
create or replace function public.set_walk_sharing(p_session_id uuid, p_enabled boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_status text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select status into v_status from public.walk_sessions where id = p_session_id;
  if v_status is null or not private.is_session_member(p_session_id) then raise exception 'not_found'; end if;
  if p_enabled and v_status <> 'active' then raise exception 'session_closed'; end if;    -- sharing can only be (re)started in a live walk
  update public.walk_session_participants
     set sharing_stopped_at = case when p_enabled then null else coalesce(sharing_stopped_at, now()) end
   where session_id = p_session_id and user_id = v_uid and (p_enabled or finished_at is null);
  return private.walk_session_json(p_session_id);
end $$;

-- "Yes, finish my walk" / "Yes, we finished". Stops my sharing. When BOTH have confirmed the walk is Completed.
-- The distance each person reports is only a hint: it is clamped to what the planned route and the elapsed time allow.
create or replace function public.finish_walk(p_session_id uuid, p_distance_m integer default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := private.require_ready();
  v_s public.walk_sessions%rowtype;
  v_route integer;
  v_secs integer;
  v_reports integer[];
  v_dist integer;
begin
  perform private.expire_walk_sessions();
  select * into v_s from public.walk_sessions where id = p_session_id for update;
  if not found or not private.is_session_member(p_session_id) then raise exception 'not_found'; end if;
  if v_s.status in ('completed') then return private.walk_session_json(p_session_id); end if;
  if v_s.status not in ('active', 'awaiting_completion') then raise exception 'session_closed'; end if;

  update public.walk_session_participants
     set finished_at = coalesce(finished_at, now()),
         completion_confirmed_at = coalesce(completion_confirmed_at, now()),
         sharing_stopped_at = coalesce(sharing_stopped_at, now()),
         reported_distance_m = coalesce(reported_distance_m, greatest(p_distance_m, 0))
   where session_id = p_session_id and user_id = v_uid;

  if exists (select 1 from public.walk_session_participants where session_id = p_session_id and completion_confirmed_at is null) then
    update public.walk_sessions
       set status = 'awaiting_completion', completion_deadline = coalesce(completion_deadline, now() + interval '24 hours')
     where id = p_session_id;
  else
    v_secs := greatest(extract(epoch from now() - v_s.started_at)::integer, 0);
    select coalesce(w.distance_meters, 0) into v_route from public.walk_routes w where w.activity_id = v_s.activity_id;
    select array_agg(reported_distance_m) into v_reports
      from public.walk_session_participants where session_id = p_session_id and reported_distance_m is not null;
    v_dist := case when v_reports is null then v_route
                   else (select avg(x)::integer from unnest(v_reports) x) end;
    v_dist := least(v_dist, greatest(v_route * 2, 300), v_secs * 3);       -- ≤ 3 m/s and ≤ twice the planned route
    update public.walk_sessions
       set status = 'completed', ended_at = now(), duration_seconds = v_secs, distance_meters = greatest(v_dist, 0)
     where id = p_session_id;
  end if;
  return private.walk_session_json(p_session_id);
end $$;

-- "We didn't finish together": either person can end the walk early. Never counted as a completed walk.
create or replace function public.end_walk_early(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_s public.walk_sessions%rowtype;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_s from public.walk_sessions where id = p_session_id for update;
  if not found or not private.is_session_member(p_session_id) then raise exception 'not_found'; end if;
  if v_s.status in ('completed', 'cancelled', 'ended_early', 'expired') then return private.walk_session_json(p_session_id); end if;
  update public.walk_sessions
     set status = case when v_s.status in ('active', 'awaiting_completion') then 'ended_early' else 'cancelled' end,
         ended_at = now(),
         duration_seconds = case when v_s.started_at is not null then extract(epoch from now() - v_s.started_at)::integer end
   where id = p_session_id;
  update public.walk_session_participants set sharing_stopped_at = coalesce(sharing_stopped_at, now()) where session_id = p_session_id;
  return private.walk_session_json(p_session_id);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Walk history & memories (one shared session row, individual participant associations)
-- ---------------------------------------------------------------------------
create or replace function public.set_walk_memory_prefs(p_session_id uuid, p_show_on_profile boolean, p_reveal_partner boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.walk_session_participants
     set show_on_profile = coalesce(p_show_on_profile, show_on_profile), reveal_partner = coalesce(p_reveal_partner, reveal_partner)
   where session_id = p_session_id and user_id = auth.uid();
end $$;

-- My completed walks, newest first. The partner's name appears only when BOTH of us opted in. No GPS, no exact places.
create or replace function public.list_my_walk_history(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return coalesce((
    select jsonb_agg(row order by (row ->> 'started_at') desc) from (
      select jsonb_build_object(
        'id', s.id, 'title', a.title, 'started_at', s.started_at,
        'duration_seconds', s.duration_seconds, 'distance_meters', s.distance_meters,
        'from_label', w.public_start_location, 'to_label', w.public_end_location, 'area', w.public_area,
        'mode', w.walk_mode,
        'partner_name', case when me.reveal_partner and other.reveal_partner then op.display_name end,
        'show_on_profile', me.show_on_profile, 'reveal_partner', me.reveal_partner) as row
      from public.walk_sessions s
      join public.walk_session_participants me on me.session_id = s.id and me.user_id = auth.uid()
      join public.walk_session_participants other on other.session_id = s.id and other.user_id <> auth.uid()
      join public.profiles op on op.id = other.user_id
      join public.activities a on a.id = s.activity_id
      left join public.walk_routes w on w.activity_id = a.id
      where s.status = 'completed'
      order by s.started_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 300)) q), '[]'::jsonb);
end $$;

create or replace function public.my_walk_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return (select jsonb_build_object('walks', count(*), 'distance_meters', coalesce(sum(s.distance_meters), 0),
                                    'duration_seconds', coalesce(sum(s.duration_seconds), 0))
          from public.walk_sessions s join public.walk_session_participants p on p.session_id = s.id and p.user_id = auth.uid()
          where s.status = 'completed');
end $$;

-- Someone else's totals, only when they chose to show them (counts only; never individual walks).
create or replace function public.profile_walk_stats(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_user <> auth.uid() and not exists (
       select 1 from public.profiles pr where pr.id = p_user and pr.show_walk_stats and not private.blocked_with(pr.id)
         and (pr.visibility = 'everyone' or private.shares_context(pr.id))) then
    return null;
  end if;
  return (select jsonb_build_object('walks', count(*), 'distance_meters', coalesce(sum(s.distance_meters), 0),
                                    'duration_seconds', coalesce(sum(s.duration_seconds), 0))
          from public.walk_sessions s join public.walk_session_participants p on p.session_id = s.id and p.user_id = p_user
          where s.status = 'completed' and (p_user = auth.uid() or p.show_on_profile));
end $$;

-- ---------------------------------------------------------------------------
-- 6. Privileges for the new functions
-- ---------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('open_walk_session', 'get_walk_session', 'set_walk_ready', 'set_walk_sharing',
                                                   'finish_walk', 'end_walk_early', 'set_walk_memory_prefs', 'list_my_walk_history',
                                                   'my_walk_stats', 'profile_walk_stats')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- Policy helpers run as the signed-in role, so it needs EXECUTE on them (same pattern as migration 3).
revoke all on function private.is_session_member(uuid), private.can_use_walk_channel(text) from public, anon;
grant execute on function private.is_session_member(uuid), private.can_use_walk_channel(text) to authenticated;
