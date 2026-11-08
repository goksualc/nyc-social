-- Along · migration 7 — walk modes ("Just Walk" / "Overthink Together"), walks-only discovery, walking profile prefs
--
-- Product pivot: Along is now a walking-companionship app. Coworking is retired from the product, but NOTHING is dropped:
-- cowork_locations, existing cowork activities, their requests and chats all stay in the database untouched.
-- Cowork plans simply stop being discoverable, and the app ignores them.
--
-- Does not modify any earlier migration. Safe to run once, after migration 6.

-- ---------------------------------------------------------------------------
-- 1. Walk modes live on walk_routes (same activity model; Overthink Together is a mode, not a new system)
-- ---------------------------------------------------------------------------
alter table public.walk_routes
  add column if not exists walk_mode text not null default 'just_walk'
    check (walk_mode in ('just_walk', 'overthink')),
  add column if not exists conversation_topic text
    check (conversation_topic in ('life_lately', 'career', 'relationships', 'existential', 'random', 'anything')),
  add column if not exists custom_topic text
    check (char_length(custom_topic) between 1 and 60),
  add column if not exists conversation_preference text
    check (conversation_preference in ('talk_it_out', 'brainstorm', 'distract_me', 'just_listen'));

-- Conversation fields only exist on Overthink Together walks.
alter table public.walk_routes
  add constraint walk_routes_conversation_only_when_overthink
  check (walk_mode = 'overthink' or (conversation_topic is null and custom_topic is null and conversation_preference is null));

-- ---------------------------------------------------------------------------
-- 2. Public card type gains the walk-mode fields (appended, so existing positions are unchanged)
-- ---------------------------------------------------------------------------
alter type public.activity_card
  add attribute walk_mode text,
  add attribute conversation_topic text,
  add attribute custom_topic text,
  add attribute conversation_preference text;

create or replace function private.cards_for(p_ids uuid[])
returns setof public.activity_card
language sql stable security definer set search_path = public, extensions as $$
  select
    a.id, a.creator_id, a.type, a.title, a.description, a.start_time, a.end_time,
    a.max_participants::integer, a.visibility, a.status, a.created_at, a.updated_at,
    (select count(*)::integer from public.join_requests r where r.activity_id = a.id and r.status = 'accepted'),
    coalesce(p.display_name, 'Someone'),
    case when p.visibility = 'everyone' then p.avatar_url end,
    coalesce(w.public_area, c.public_area),
    w.public_start_location, w.public_end_location, w.pace, c.work_style,
    ST_X(coalesce(w.public_start_point, c.public_point)::geometry),
    ST_Y(coalesce(w.public_start_point, c.public_point)::geometry),
    ST_X(w.public_end_point::geometry),
    ST_Y(w.public_end_point::geometry),
    a.creator_id = auth.uid(),
    exists (select 1 from public.join_requests r
            where r.activity_id = a.id and r.requester_id = auth.uid() and r.status = 'accepted'),
    w.walk_mode, w.conversation_topic, w.custom_topic, w.conversation_preference
  from public.activities a
  join public.profiles p on p.id = a.creator_id
  left join public.walk_routes w on w.activity_id = a.id
  left join public.cowork_locations c on c.activity_id = a.id
  where a.id = any (p_ids)
  order by array_position(p_ids, a.id)
$$;

-- ---------------------------------------------------------------------------
-- 3. create_walk — the old signature is replaced (an extra overload would make PostgREST calls ambiguous)
-- ---------------------------------------------------------------------------
drop function if exists public.create_walk(
  text, text, timestamptz, timestamptz, integer, text, text, text, text,
  double precision, double precision, double precision, double precision, jsonb, text);

create or replace function public.create_walk(
  p_title text, p_description text, p_start_time timestamptz, p_end_time timestamptz,
  p_max_participants integer, p_visibility text, p_pace text,
  p_start_label text, p_end_label text,
  p_start_lng double precision, p_start_lat double precision,
  p_end_lng double precision, p_end_lat double precision,
  p_route jsonb default null, p_meeting_details text default '',
  p_walk_mode text default 'just_walk', p_conversation_topic text default null,
  p_custom_topic text default null, p_conversation_preference text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := private.require_ready();
  v_id uuid;
  v_start geography; v_end geography; v_route geography;
  v_pstart geography; v_pend geography;
  v_area text;
begin
  perform private.validate_activity(p_title, p_description, p_start_time, p_end_time, p_max_participants, p_visibility);
  if p_pace not in ('casual', 'moderate', 'fast') then raise exception 'invalid_pace'; end if;
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

  insert into public.activities (creator_id, type, title, description, start_time, end_time, max_participants, visibility)
  values (v_uid, 'walk', btrim(p_title), btrim(coalesce(p_description, '')), p_start_time, p_end_time, p_max_participants, p_visibility)
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

-- create_cowork stays installed (history, tests) but is no longer callable from the app.
revoke execute on function public.create_cowork(text, text, timestamptz, timestamptz, integer, text, text, text, text, double precision, double precision, text, text) from authenticated;

-- ---------------------------------------------------------------------------
-- 4. Discovery is walks-only (cowork rows are never returned, whatever the client asks for)
-- ---------------------------------------------------------------------------
create or replace function public.discover_activities(
  p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision,
  p_type text default null, p_from timestamptz default null, p_to timestamptz default null,
  p_limit integer default 50, p_offset integer default 0)
returns setof public.activity_card
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_env geography;
  v_ids uuid[];
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_from timestamptz := greatest(now(), coalesce(p_from, now()));
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_type is not null and p_type <> 'walk' then raise exception 'invalid_type'; end if;
  if p_min_lng is null or p_min_lat is null or p_max_lng is null or p_max_lat is null
     or p_min_lng >= p_max_lng or p_min_lat >= p_max_lat
     or p_max_lng - p_min_lng > 0.6 or p_max_lat - p_min_lat > 0.6 then
    raise exception 'invalid_bounds';
  end if;
  v_env := ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography;

  select coalesce(array_agg(s.id order by s.start_time, s.id), '{}') into v_ids from (
    select u.id, u.start_time from (
      select a.id, a.start_time from public.activities a
      join public.walk_routes w on w.activity_id = a.id
      where a.visibility = 'public' and a.status = 'active' and a.end_time > v_from
        and (p_to is null or a.start_time < p_to)
        and (p_type is null or a.type = p_type)
        and ST_Intersects(w.public_route_geometry, v_env)
        and not private.blocked_with(a.creator_id)
    ) u
    order by u.start_time, u.id
    limit v_limit offset v_offset
  ) s;

  return query select * from private.cards_for(v_ids);
end $$;

create or replace function public.nearby_activities(
  p_lng double precision, p_lat double precision, p_radius_m double precision default 2000,
  p_type text default null, p_limit integer default 50)
returns setof public.activity_card
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_pt geography;
  v_ids uuid[];
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_type is not null and p_type <> 'walk' then raise exception 'invalid_type'; end if;
  if p_lng is null or p_lat is null or p_radius_m is null or p_radius_m <= 0 or p_radius_m > 20000 then
    raise exception 'invalid_bounds';
  end if;
  v_pt := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  select coalesce(array_agg(s.id order by s.dist, s.id), '{}') into v_ids from (
    select u.id, u.dist from (
      select a.id, ST_Distance(w.public_start_point, v_pt) as dist from public.activities a
      join public.walk_routes w on w.activity_id = a.id
      where a.visibility = 'public' and a.status = 'active' and a.end_time > now()
        and (p_type is null or a.type = p_type)
        and ST_DWithin(w.public_start_point, v_pt, p_radius_m)
        and not private.blocked_with(a.creator_id)
    ) u
    order by u.dist, u.id
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) s;

  return query select * from private.cards_for(v_ids);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Walking profile preferences (all optional, none sensitive)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists favorite_neighborhoods text[] not null default '{}'
    check (cardinality(favorite_neighborhoods) <= 5),
  add column if not exists preferred_pace text
    check (preferred_pace in ('casual', 'moderate', 'fast')),
  add column if not exists discussion_topics text[] not null default '{}'
    check (cardinality(discussion_topics) <= 6
           and discussion_topics <@ array['life_lately','career','relationships','existential','random','anything']);

grant select (favorite_neighborhoods, preferred_pace, discussion_topics) on public.profiles to authenticated;
grant update (favorite_neighborhoods, preferred_pace, discussion_topics) on public.profiles to authenticated;

-- looking_for no longer offers coworking; existing values stay valid.
drop function if exists public.get_my_profile();
create or replace function public.get_my_profile()
returns table (id uuid, username text, full_name text, display_name text, bio text, avatar_url text,
               interests text[], looking_for text[], visibility text, age_confirmed_at timestamptz,
               created_at timestamptz, updated_at timestamptz,
               favorite_neighborhoods text[], preferred_pace text, discussion_topics text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select p.id, p.username, p.full_name, p.display_name, p.bio, p.avatar_url, p.interests, p.looking_for,
           p.visibility, p.age_confirmed_at, p.created_at, p.updated_at,
           p.favorite_neighborhoods, p.preferred_pace, p.discussion_topics
    from public.profiles p where p.id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- 6. Privileges for the (re)created functions
-- ---------------------------------------------------------------------------
revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('create_walk', 'discover_activities', 'nearby_activities')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
