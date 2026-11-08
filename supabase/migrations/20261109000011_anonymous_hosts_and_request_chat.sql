-- Along · migration 11 — anonymous organizers, masked chat identities, and messaging before a request is accepted
--
-- 1. "Private" walks are redefined: the WALK is public and on the map; only the ORGANIZER's identity is hidden.
--    Existing private (hidden) walks keep their old visibility until their owner explicitly converts them.
-- 2. Everything a client can read about a hidden organizer is masked on the server: activity cards, conversations,
--    messages, walk sessions, realtime payloads. The real user id never reaches another user's device.
-- 3. The organizer can start a chat with an applicant while the request is still pending.
--
-- Additive. Does not modify earlier migrations. Run once, after migration 10.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
alter table public.activities
  add column if not exists host_anonymous   boolean     not null default false,
  add column if not exists host_revealed_at timestamptz,
  -- A random stand-in for the organizer, unrelated to their user id. This is all other users ever see.
  add column if not exists host_alias       uuid        not null default gen_random_uuid(),
  -- Interests the organizer chose to show on an anonymous walk (nothing else about them is shown).
  add column if not exists host_interests   text[]      not null default '{}' check (cardinality(host_interests) <= 4);

alter table public.conversations
  add column if not exists request_id uuid references public.join_requests (id) on delete set null;
create unique index if not exists conversations_one_per_request on public.conversations (request_id) where request_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Masking helpers
-- ---------------------------------------------------------------------------
-- Is this organizer hidden from the person looking? (The organizer always sees themselves.)
create or replace function private.host_concealed_for_viewer(p_anonymous boolean, p_revealed timestamptz, p_creator uuid)
returns boolean language sql stable set search_path = public as $$
  select coalesce(p_anonymous, false) and p_revealed is null and p_creator is distinct from auth.uid()
$$;

create or replace function private.host_concealed_for_viewer(p_anonymous boolean, p_revealed timestamptz, p_user uuid, p_creator uuid)
returns boolean language sql stable set search_path = public as $$
  select coalesce(p_anonymous, false) and p_revealed is null and p_user = p_creator and p_creator is distinct from auth.uid()
$$;

-- "anon:<alias>" for a hidden organizer, the plain user id for everyone else.
create or replace function private.mask_user(p_activity uuid, p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when a.host_anonymous and a.host_revealed_at is null and a.creator_id = p_user and p_user is distinct from auth.uid()
              then 'anon:' || a.host_alias::text
              else p_user::text end
  from public.activities a where a.id = p_activity
$$;

create or replace function private.host_concealed(p_activity uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.host_anonymous and a.host_revealed_at is null from public.activities a where a.id = p_activity), false)
$$;

-- ---------------------------------------------------------------------------
-- 3. Row-level: nobody but the organizer can read a hidden organizer's activity row (it carries creator_id)
-- ---------------------------------------------------------------------------
drop policy if exists activities_select on public.activities;
create policy activities_select on public.activities for select to authenticated
  using (private.can_see_activity(id)
         and (creator_id = auth.uid() or not (host_anonymous and host_revealed_at is null)));

-- ---------------------------------------------------------------------------
-- 4. Public card: creator id / name / avatar masked, interests added
-- ---------------------------------------------------------------------------
alter type public.activity_card alter attribute creator_id type text;
alter type public.activity_card
  add attribute host_anonymous boolean,
  add attribute host_interests text[];

create or replace function private.cards_for(p_ids uuid[])
returns setof public.activity_card
language sql stable security definer set search_path = public, extensions as $$
  select
    a.id, private.mask_user(a.id, a.creator_id), a.type, a.title, a.description, a.start_time, a.end_time,
    a.max_participants::integer, a.visibility, a.status, a.created_at, a.updated_at,
    (select count(*)::integer from public.join_requests r where r.activity_id = a.id and r.status = 'accepted'),
    case when private.host_concealed_for_viewer(a.host_anonymous, a.host_revealed_at, a.creator_id) then 'Anonymous Walker'
         else coalesce(p.display_name, 'Someone') end,
    case when private.host_concealed_for_viewer(a.host_anonymous, a.host_revealed_at, a.creator_id) then null
         when p.visibility = 'everyone' then p.avatar_url end,
    coalesce(w.public_area, c.public_area),
    w.public_start_location, w.public_end_location, w.pace, c.work_style,
    ST_X(coalesce(w.public_start_point, c.public_point)::geometry),
    ST_Y(coalesce(w.public_start_point, c.public_point)::geometry),
    ST_X(w.public_end_point::geometry),
    ST_Y(w.public_end_point::geometry),
    a.creator_id = auth.uid(),
    exists (select 1 from public.join_requests r
            where r.activity_id = a.id and r.requester_id = auth.uid() and r.status = 'accepted'),
    w.walk_mode, w.conversation_topic, w.custom_topic, w.conversation_preference,
    (a.host_anonymous and a.host_revealed_at is null),
    case when a.host_anonymous and a.host_revealed_at is null then a.host_interests else '{}'::text[] end
  from public.activities a
  join public.profiles p on p.id = a.creator_id
  left join public.walk_routes w on w.activity_id = a.id
  left join public.cowork_locations c on c.activity_id = a.id
  where a.id = any (p_ids)
  order by array_position(p_ids, a.id)
$$;

-- ---------------------------------------------------------------------------
-- 5. create_walk: anonymous organizer (and "private" now means anonymous, never hidden)
-- ---------------------------------------------------------------------------
drop function if exists public.create_walk(
  text, text, timestamptz, timestamptz, integer, text, text, text, text,
  double precision, double precision, double precision, double precision, jsonb, text,
  text, text, text, text);

create or replace function public.create_walk(
  p_title text, p_description text, p_start_time timestamptz, p_end_time timestamptz,
  p_max_participants integer, p_visibility text, p_pace text,
  p_start_label text, p_end_label text,
  p_start_lng double precision, p_start_lat double precision,
  p_end_lng double precision, p_end_lat double precision,
  p_route jsonb default null, p_meeting_details text default '',
  p_walk_mode text default 'just_walk', p_conversation_topic text default null,
  p_custom_topic text default null, p_conversation_preference text default null,
  p_anonymous_host boolean default false, p_host_interests text[] default '{}')
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := private.require_ready();
  v_id uuid;
  v_start geography; v_end geography; v_route geography;
  v_pstart geography; v_pend geography;
  v_area text;
  v_anon boolean := coalesce(p_anonymous_host, false) or p_visibility = 'private';   -- "private" now means: on the map, identity hidden
  v_interests text[] := coalesce(p_host_interests, '{}');
begin
  perform private.validate_activity(p_title, p_description, p_start_time, p_end_time, p_max_participants, p_visibility);
  if p_pace not in ('casual', 'moderate', 'fast') then raise exception 'invalid_pace'; end if;
  if cardinality(v_interests) > 4 or exists (select 1 from unnest(v_interests) i where char_length(btrim(i)) not between 1 and 30) then
    raise exception 'invalid_interests';
  end if;
  p_walk_mode := coalesce(p_walk_mode, 'just_walk');
  if p_walk_mode not in ('just_walk', 'overthink') then raise exception 'invalid_walk_mode'; end if;
  p_custom_topic := nullif(btrim(coalesce(p_custom_topic, '')), '');
  if p_walk_mode = 'overthink' then
    if p_conversation_topic not in ('life_lately','career','relationships','existential','random','anything')
       or p_conversation_preference not in ('talk_it_out','brainstorm','distract_me','just_listen') then
      raise exception 'invalid_conversation';
    end if;
    if p_custom_topic is not null and char_length(p_custom_topic) > 60 then raise exception 'invalid_conversation'; end if;
  else
    p_conversation_topic := null; p_custom_topic := null; p_conversation_preference := null;   -- Just Walk carries no conversation fields
  end if;
  if char_length(coalesce(p_meeting_details, '')) > 200 then raise exception 'invalid_description'; end if;
  if p_start_lng is null or p_start_lat is null or p_end_lng is null or p_end_lat is null then raise exception 'invalid_route'; end if;
  if not private.is_in_manhattan(p_start_lng, p_start_lat) or not private.is_in_manhattan(p_end_lng, p_end_lat) then
    raise exception 'outside_manhattan';
  end if;

  v_start := ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography;
  v_end   := ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography;
  if ST_Distance(v_start, v_end) < 50 then raise exception 'same_location'; end if;

  -- Use the client's walking route when it supplies one (≤ 1000 vertices, every vertex within 400 m of the island),
  -- otherwise a straight line. The stored distance is always computed server-side.
  if p_route is not null and jsonb_typeof(p_route) = 'array' and jsonb_array_length(p_route) between 2 and 1000 then
    begin
      select ST_MakeLine(array(
               select ST_SetSRID(ST_MakePoint((e.value ->> 0)::double precision, (e.value ->> 1)::double precision), 4326)
               from jsonb_array_elements(p_route) with ordinality as e(value, ord)
               order by e.ord))::geography
        into v_route;
    exception when others then
      raise exception 'invalid_route';
    end;
    if v_route is null
       or exists (select 1 from jsonb_array_elements(p_route) e
                  where not private.is_near_manhattan((e.value ->> 0)::double precision, (e.value ->> 1)::double precision)) then
      raise exception 'invalid_route';
    end if;
  else
    v_route := ST_MakeLine(v_start::geometry, v_end::geometry)::geography;
  end if;

  v_pstart := private.snap_to_public_grid(v_start);
  v_pend   := private.snap_to_public_grid(v_end);
  v_area   := private.nearest_neighborhood(v_start);

  insert into public.activities (creator_id, type, title, description, start_time, end_time, max_participants, visibility,
                                 host_anonymous, host_interests)
  values (v_uid, 'walk', btrim(p_title), btrim(coalesce(p_description, '')), p_start_time, p_end_time, p_max_participants, 'public',
          v_anon, case when v_anon then (select coalesce(array_agg(btrim(i)), '{}') from unnest(v_interests) i) else '{}' end)
  returning id into v_id;

  insert into public.walk_routes (activity_id, pace, public_start_location, public_end_location, public_area,
                                  public_start_point, public_end_point, public_route_geometry,
                                  start_coordinates, end_coordinates, route_geometry, distance_meters, meeting_details,
                                  walk_mode, conversation_topic, custom_topic, conversation_preference)
  values (v_id, p_pace,
          private.safe_label(p_start_label, private.nearest_neighborhood(v_start)),
          private.safe_label(p_end_label, private.nearest_neighborhood(v_end)),
          v_area, v_pstart, v_pend,
          ST_MakeLine(v_pstart::geometry, v_pend::geometry)::geography,   -- degenerate when both snap to one cell
          v_start, v_end, v_route, greatest(round(ST_Length(v_route))::integer, 50),
          btrim(coalesce(p_meeting_details, '')),
          p_walk_mode, p_conversation_topic, p_custom_topic, p_conversation_preference);
  return v_id;
exception when check_violation or numeric_value_out_of_range then
  raise exception 'invalid_route';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Owner controls: reveal, or opt a legacy hidden walk into the new anonymous mode
-- ---------------------------------------------------------------------------
create or replace function public.reveal_walk_host(p_activity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.activities set host_revealed_at = coalesce(host_revealed_at, now())
   where id = p_activity_id and creator_id = auth.uid() and host_anonymous;
  if not found then raise exception 'not_found'; end if;
end $$;

-- Explicit, owner-only: a legacy private (hidden) walk becomes a public walk with an anonymous organizer.
create or replace function public.make_walk_anonymous_public(p_activity_id uuid, p_host_interests text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare v text[] := coalesce(p_host_interests, '{}');
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if cardinality(v) > 4 or exists (select 1 from unnest(v) i where char_length(btrim(i)) not between 1 and 30) then
    raise exception 'invalid_interests';
  end if;
  update public.activities
     set visibility = 'public', host_anonymous = true, host_revealed_at = null,
         host_interests = (select coalesce(array_agg(btrim(i)), '{}') from unnest(v) i)
   where id = p_activity_id and creator_id = auth.uid() and status = 'active';
  if not found then raise exception 'not_found'; end if;
end $$;

-- Block the organizer of an anonymous walk without learning who they are. The block row is hidden from the blocker
-- (it would otherwise hand them the real user id) and still severs requests and messaging.
alter table public.user_blocks add column if not exists concealed boolean not null default false;
drop policy if exists user_blocks_select_own on public.user_blocks;
create policy user_blocks_select_own on public.user_blocks for select to authenticated
  using (blocker_id = auth.uid() and not concealed);

create or replace function public.block_walk_host(p_activity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_host uuid; v_hidden boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select a.creator_id, (a.host_anonymous and a.host_revealed_at is null) into v_host, v_hidden
    from public.activities a where a.id = p_activity_id;
  if v_host is null or v_host = v_uid then raise exception 'not_allowed'; end if;
  insert into public.user_blocks (blocker_id, blocked_id, blocked_display_name, concealed)
  values (v_uid, v_host, case when v_hidden then 'Anonymous Walker' else (select display_name from public.profiles where id = v_host) end, v_hidden)
  on conflict do nothing;
  update public.join_requests r set status = 'cancelled'
   where r.status in ('pending', 'accepted')
     and exists (select 1 from public.activities a where a.id = r.activity_id
                 and ((a.creator_id = v_uid and r.requester_id = v_host) or (a.creator_id = v_host and r.requester_id = v_uid)));
end $$;

-- ---------------------------------------------------------------------------
-- 7. Messaging before acceptance
-- ---------------------------------------------------------------------------
-- A chat accepts messages while: the viewer is in it, nobody is blocked, the plan isn't cancelled, and EVERY guest in it
-- either holds an accepted request, or holds a pending one for a plan that hasn't ended yet (pre-approval chat).
-- Declined / cancelled / withdrawn requests, and pending requests on ended plans, close the conversation.
create or replace function private.can_message(p_conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.conversations c
    join public.activities a on a.id = c.activity_id
    where c.id = p_conversation
      and a.status <> 'cancelled'
      and private.in_conversation(c.id)
      and not private.conversation_blocked(c.id)
      and exists (select 1 from public.conversation_participants g where g.conversation_id = c.id and g.user_id <> a.creator_id)
      and not exists (
        select 1 from public.conversation_participants g
        where g.conversation_id = c.id and g.user_id <> a.creator_id
          and not exists (select 1 from public.join_requests r
                          where r.activity_id = a.id and r.requester_id = g.user_id
                            and (r.status = 'accepted' or (r.status = 'pending' and a.end_time > now()))))
  )
$$;

-- Only the organizer can open the conversation; the applicant can answer once it exists. Idempotent: one chat per request.
create or replace function public.start_request_conversation(p_request_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := private.require_ready();
  r public.join_requests;
  a public.activities;
  v_conv uuid;
begin
  select * into r from public.join_requests where id = p_request_id;
  if not found then raise exception 'not_found'; end if;
  select * into a from public.activities where id = r.activity_id;
  if a.creator_id <> v_uid then raise exception 'not_found'; end if;                 -- only the organizer
  if r.status not in ('pending', 'accepted') then raise exception 'request_not_pending'; end if;
  if a.status <> 'active' or a.end_time <= now() then raise exception 'activity_closed'; end if;
  if private.blocked_with(r.requester_id) then raise exception 'blocked'; end if;

  perform pg_advisory_xact_lock(hashtext(p_request_id::text));
  select c.id into v_conv from public.conversations c
   where c.activity_id = a.id
     and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = a.creator_id)
     and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = r.requester_id)
   limit 1;
  if v_conv is null then
    insert into public.conversations (activity_id, request_id) values (a.id, r.id) returning id into v_conv;
    insert into public.conversation_participants (conversation_id, user_id) values (v_conv, a.creator_id), (v_conv, r.requester_id);
  end if;
  return v_conv;
end $$;

-- Abuse protection: at most 20 messages a minute per person, and an organizer can send at most 5 messages to an applicant
-- who hasn't answered yet.
create or replace function private.enforce_message_limits()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_creator uuid; v_last_guest timestamptz;
begin
  if (select count(*) from public.messages where sender_id = new.sender_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'rate_limited';
  end if;
  select a.creator_id into v_creator from public.conversations c join public.activities a on a.id = c.activity_id where c.id = new.conversation_id;
  if new.sender_id = v_creator then
    select max(created_at) into v_last_guest from public.messages where conversation_id = new.conversation_id and sender_id <> v_creator;
    if (select count(*) from public.messages
         where conversation_id = new.conversation_id and sender_id = v_creator
           and created_at > coalesce(v_last_guest, '-infinity')) >= 5 then
      raise exception 'rate_limited';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists messages_enforce_limits on public.messages;
create trigger messages_enforce_limits before insert on public.messages for each row execute function private.enforce_message_limits();

-- ---------------------------------------------------------------------------
-- 8. Chat reads and writes go through RPCs that mask a hidden organizer's id
-- ---------------------------------------------------------------------------
create or replace function public.list_my_conversations()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'activity_id', c.activity_id, 'request_id', c.request_id, 'created_at', c.created_at,
             'conversation_participants', (select jsonb_agg(jsonb_build_object('user_id', private.mask_user(c.activity_id, cp.user_id)))
                                             from public.conversation_participants cp where cp.conversation_id = c.id))
           order by c.created_at desc)
    from public.conversations c
    where private.in_conversation(c.id) and not private.conversation_blocked(c.id)), '[]'::jsonb);
end $$;

create or replace function public.list_my_messages(p_conversation uuid default null, p_before timestamptz default null, p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q.id, 'conversation_id', q.conversation_id,
                                        'sender_id', private.mask_user(q.activity_id, q.sender_id),
                                        'content', q.content, 'created_at', q.created_at)
                     order by q.created_at desc, q.id desc)
    from (select m.id, m.conversation_id, m.sender_id, m.content, m.created_at, c.activity_id
            from public.messages m join public.conversations c on c.id = m.conversation_id
           where private.in_conversation(c.id) and not private.conversation_blocked(c.id)
             and (p_conversation is null or c.id = p_conversation)
             and (p_before is null or m.created_at < p_before)
           order by m.created_at desc, m.id desc
           limit least(greatest(coalesce(p_limit, 200), 1), 300)) q), '[]'::jsonb);
end $$;

create or replace function public.send_message(p_conversation uuid, p_content text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_text text := btrim(coalesce(p_content, '')); m public.messages; v_activity uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if char_length(v_text) not between 1 and 2000 then raise exception 'not_allowed'; end if;
  if not private.can_message(p_conversation) then raise exception 'chat_closed'; end if;
  insert into public.messages (conversation_id, sender_id, content) values (p_conversation, v_uid, v_text) returning * into m;
  select activity_id into v_activity from public.conversations where id = p_conversation;
  return jsonb_build_object('id', m.id, 'conversation_id', m.conversation_id, 'sender_id', private.mask_user(v_activity, m.sender_id),
                            'content', m.content, 'created_at', m.created_at);
end $$;

-- Clients may no longer read or write these tables directly (the raw rows carry real user ids).
revoke select on public.messages, public.conversation_participants from authenticated;
revoke insert on public.messages from authenticated;

-- ---------------------------------------------------------------------------
-- 9. Realtime without identities: a tiny "something happened in conversation X" table replaces row streaming of
--    messages / participants (whose payloads would carry real user ids).
-- ---------------------------------------------------------------------------
create table if not exists public.chat_pings (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  kind            text not null check (kind in ('message', 'conversation')),
  created_at      timestamptz not null default now()
);
create index if not exists chat_pings_created_idx on public.chat_pings (created_at);
alter table public.chat_pings enable row level security;
revoke all on public.chat_pings from anon, authenticated;
drop policy if exists chat_pings_select on public.chat_pings;
create policy chat_pings_select on public.chat_pings for select to authenticated using (private.in_conversation(conversation_id));
grant select (id, conversation_id, kind, created_at) on public.chat_pings to authenticated;

create or replace function private.ping_message() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.chat_pings (conversation_id, kind) values (new.conversation_id, 'message');
  delete from public.chat_pings where created_at < now() - interval '1 day';
  return new;
end $$;
drop trigger if exists messages_ping on public.messages;
create trigger messages_ping after insert on public.messages for each row execute function private.ping_message();

create or replace function private.ping_conversation() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.conversation_participants where conversation_id = new.conversation_id) >= 2 then
    insert into public.chat_pings (conversation_id, kind) values (new.conversation_id, 'conversation');
  end if;
  return new;
end $$;
drop trigger if exists participants_ping on public.conversation_participants;
create trigger participants_ping after insert on public.conversation_participants for each row execute function private.ping_conversation();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime drop table public.messages; exception when undefined_object then null; end;
    begin alter publication supabase_realtime drop table public.conversation_participants; exception when undefined_object then null; end;
    begin alter publication supabase_realtime add table public.chat_pings; exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Walk sessions: the same masking for live walks with an anonymous organizer
-- ---------------------------------------------------------------------------
create or replace function private.walk_session_json(p_session uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'activity_id', s.activity_id, 'status', s.status,
    'started_at', s.started_at, 'ended_at', s.ended_at,
    'duration_seconds', s.duration_seconds, 'distance_meters', s.distance_meters,
    'completion_deadline', s.completion_deadline,
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', private.mask_user(s.activity_id, p.user_id), 'role', p.role,
               'display_name', case when private.host_concealed_for_viewer(act.host_anonymous, act.host_revealed_at, p.user_id, act.creator_id)
                                    then 'Anonymous Walker' else coalesce(pr.display_name, 'Someone') end,
               'avatar_path', case when private.host_concealed_for_viewer(act.host_anonymous, act.host_revealed_at, p.user_id, act.creator_id) then null
                                   when pr.visibility = 'everyone' or p.user_id = auth.uid() then pr.avatar_url end,
               'joined_at', p.joined_at, 'ready_at', p.ready_at,
               'completion_confirmed_at', p.completion_confirmed_at, 'sharing_stopped_at', p.sharing_stopped_at)
             order by p.role desc)
        from public.walk_session_participants p join public.profiles pr on pr.id = p.user_id
       where p.session_id = s.id), '[]'::jsonb))
  from public.walk_sessions s join public.activities act on act.id = s.activity_id where s.id = p_session
$$;

-- ---------------------------------------------------------------------------
-- 11. Privileges
-- ---------------------------------------------------------------------------
grant execute on function private.host_concealed_for_viewer(boolean, timestamptz, uuid), private.host_concealed_for_viewer(boolean, timestamptz, uuid, uuid),
  private.mask_user(uuid, uuid), private.host_concealed(uuid) to authenticated;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('create_walk', 'reveal_walk_host', 'make_walk_anonymous_public', 'block_walk_host',
                                                   'start_request_conversation', 'list_my_conversations', 'list_my_messages', 'send_message')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
