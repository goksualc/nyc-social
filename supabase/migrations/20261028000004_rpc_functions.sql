-- Along · migration 4 — secure RPC functions
--
-- All public RPCs are SECURITY DEFINER with a pinned search_path, derive identity from auth.uid() (never from a
-- parameter), validate everything server-side, and raise short machine-readable error codes
-- (e.g. 'activity_full') that the iOS app maps to friendly messages.

-- ---------------------------------------------------------------------------
-- Shared return type for discovery / my plans
-- ---------------------------------------------------------------------------
create type public.activity_card as (
  id                    uuid,
  creator_id            uuid,
  type                  text,
  title                 text,
  description           text,
  start_time            timestamptz,
  end_time              timestamptz,
  max_participants      integer,
  visibility            text,
  status                text,
  created_at            timestamptz,
  updated_at            timestamptz,
  participant_count     integer,
  host_name             text,
  host_avatar_path      text,
  public_area           text,
  start_label           text,
  end_label             text,
  pace                  text,
  work_style            text,
  start_lng             double precision,
  start_lat             double precision,
  end_lng               double precision,
  end_lat               double precision,
  viewer_is_creator     boolean,
  viewer_is_participant boolean
);

-- Builds cards (PUBLIC data only) for already-authorised ids, preserving the order of `p_ids`.
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
            where r.activity_id = a.id and r.requester_id = auth.uid() and r.status = 'accepted')
  from public.activities a
  join public.profiles p on p.id = a.creator_id
  left join public.walk_routes w on w.activity_id = a.id
  left join public.cowork_locations c on c.activity_id = a.id
  where a.id = any (p_ids)
  order by array_position(p_ids, a.id)
$$;

create or replace function private.require_ready()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_ok  boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select (display_name is not null and age_confirmed_at is not null) into v_ok from public.profiles where id = v_uid;
  if not coalesce(v_ok, false) then raise exception 'profile_incomplete'; end if;
  return v_uid;
end $$;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create or replace function public.ensure_profile()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;   -- never overwrites
end $$;

create or replace function public.get_my_profile()
returns table (id uuid, username text, full_name text, display_name text, bio text, avatar_url text,
               interests text[], looking_for text[], visibility text, age_confirmed_at timestamptz,
               created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select p.id, p.username, p.full_name, p.display_name, p.bio, p.avatar_url, p.interests, p.looking_for,
           p.visibility, p.age_confirmed_at, p.created_at, p.updated_at
    from public.profiles p where p.id = auth.uid();
end $$;

-- First-run profile completion. Also records the 18+ confirmation (server-side timestamp).
create or replace function public.complete_profile(
  p_display_name text, p_bio text default '', p_interests text[] default '{}',
  p_looking_for text[] default '{}', p_confirm_age boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  p_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(p_display_name) not between 1 and 24 then raise exception 'invalid_name'; end if;
  perform public.ensure_profile();
  update public.profiles set
    display_name = p_display_name,
    bio = left(btrim(coalesce(p_bio, '')), 160),
    interests = coalesce(p_interests, '{}'),
    looking_for = coalesce(p_looking_for, '{}'),
    age_confirmed_at = coalesce(age_confirmed_at, case when p_confirm_age then now() end)
  where id = v_uid;
  if not exists (select 1 from public.profiles where id = v_uid and age_confirmed_at is not null) then
    raise exception 'age_required';
  end if;
end $$;

-- Deletes the auth user; every owned row cascades (profile, activities, requests, messages, blocks).
-- The client must remove the avatar object through the Storage API first (SQL can't delete S3 objects).
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- Creating activities (atomic: the activity and its location row are written in one transaction)
-- ---------------------------------------------------------------------------
create or replace function private.validate_activity(
  p_title text, p_description text, p_start timestamptz, p_end timestamptz, p_max int, p_visibility text)
returns void language plpgsql stable set search_path = public as $$
begin
  if p_title is null or char_length(btrim(p_title)) not between 1 and 80 then raise exception 'invalid_title'; end if;
  if char_length(coalesce(p_description, '')) > 280 then raise exception 'invalid_description'; end if;
  if p_start is null or p_end is null or p_start < now() - interval '2 minutes' then raise exception 'start_in_past'; end if;
  if p_end <= p_start or p_end > p_start + interval '12 hours' then raise exception 'invalid_times'; end if;
  if p_start > now() + interval '60 days' then raise exception 'too_far_ahead'; end if;
  if p_max is null or p_max not between 1 and 5 then raise exception 'invalid_capacity'; end if;
  if p_visibility not in ('public', 'private') then raise exception 'invalid_visibility'; end if;
end $$;

-- Public labels must never be street addresses; fall back to the neighbourhood if they look like one.
create or replace function private.safe_label(p_label text, p_fallback text)
returns text language sql immutable as $$
  select case
    when p_label is null or btrim(p_label) = '' or btrim(p_label) ~ '^\d+\s' or char_length(btrim(p_label)) > 60
      then p_fallback
    else btrim(p_label)
  end
$$;

create or replace function public.create_walk(
  p_title text, p_description text, p_start_time timestamptz, p_end_time timestamptz,
  p_max_participants integer, p_visibility text, p_pace text,
  p_start_label text, p_end_label text,
  p_start_lng double precision, p_start_lat double precision,
  p_end_lng double precision, p_end_lat double precision,
  p_route jsonb default null, p_meeting_details text default '')
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
                                  start_coordinates, end_coordinates, route_geometry, distance_meters, meeting_details)
  values (v_id, p_pace,
          private.safe_label(p_start_label, private.nearest_neighborhood(v_start)),
          private.safe_label(p_end_label, private.nearest_neighborhood(v_end)),
          v_area, v_pstart, v_pend,
          ST_MakeLine(v_pstart::geometry, v_pend::geometry)::geography,   -- degenerate when both snap to one cell
          v_start, v_end, v_route, greatest(round(ST_Length(v_route))::integer, 50),
          btrim(coalesce(p_meeting_details, '')));
  return v_id;
exception when check_violation or numeric_value_out_of_range then
  raise exception 'invalid_route';
end $$;

create or replace function public.create_cowork(
  p_title text, p_description text, p_start_time timestamptz, p_end_time timestamptz,
  p_max_participants integer, p_visibility text, p_work_style text,
  p_cafe_name text, p_address text, p_lng double precision, p_lat double precision,
  p_place_identifier text default null, p_meeting_details text default '')
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := private.require_ready();
  v_id uuid;
  v_point geography;
begin
  perform private.validate_activity(p_title, p_description, p_start_time, p_end_time, p_max_participants, p_visibility);
  if p_work_style not in ('deep_work', 'social', 'build_together') then raise exception 'invalid_work_style'; end if;
  if p_cafe_name is null or btrim(p_cafe_name) = '' then raise exception 'invalid_location'; end if;
  if char_length(coalesce(p_meeting_details, '')) > 200 then raise exception 'invalid_description'; end if;
  if p_lng is null or p_lat is null or not private.is_in_manhattan(p_lng, p_lat) then raise exception 'outside_manhattan'; end if;

  v_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  insert into public.activities (creator_id, type, title, description, start_time, end_time, max_participants, visibility)
  values (v_uid, 'cowork', btrim(p_title), btrim(coalesce(p_description, '')), p_start_time, p_end_time, p_max_participants, p_visibility)
  returning id into v_id;

  insert into public.cowork_locations (activity_id, work_style, public_area, public_point, cafe_name, address,
                                       latitude, longitude, place_identifier, meeting_details)
  values (v_id, p_work_style, private.nearest_neighborhood(v_point), private.snap_to_public_grid(v_point),
          btrim(p_cafe_name), nullif(btrim(coalesce(p_address, '')), ''), p_lat, p_lng,
          nullif(btrim(coalesce(p_place_identifier, '')), ''), btrim(coalesce(p_meeting_details, '')));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Editing and cancelling (creator only)
-- ---------------------------------------------------------------------------
create or replace function public.update_activity(
  p_activity_id uuid, p_title text default null, p_description text default null,
  p_start_time timestamptz default null, p_end_time timestamptz default null,
  p_max_participants integer default null, p_meeting_details text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := private.require_ready();
  a public.activities;
  v_accepted integer;
begin
  select * into a from public.activities where id = p_activity_id for update;
  if not found or a.creator_id <> v_uid then raise exception 'not_found'; end if;
  if a.status <> 'active' or a.end_time <= now() then raise exception 'activity_closed'; end if;

  select count(*) into v_accepted from public.join_requests where activity_id = a.id and status = 'accepted';
  perform private.validate_activity(
    coalesce(p_title, a.title), coalesce(p_description, a.description),
    coalesce(p_start_time, a.start_time), coalesce(p_end_time, a.end_time),
    coalesce(p_max_participants, a.max_participants), a.visibility);
  if coalesce(p_max_participants, a.max_participants) < v_accepted then raise exception 'capacity_below_accepted'; end if;

  update public.activities set
    title = btrim(coalesce(p_title, title)),
    description = btrim(coalesce(p_description, description)),
    start_time = coalesce(p_start_time, start_time),
    end_time = coalesce(p_end_time, end_time),
    max_participants = coalesce(p_max_participants, max_participants)
  where id = a.id;

  if p_meeting_details is not null then
    if char_length(p_meeting_details) > 200 then raise exception 'invalid_description'; end if;
    update public.walk_routes set meeting_details = btrim(p_meeting_details) where activity_id = a.id;
    update public.cowork_locations set meeting_details = btrim(p_meeting_details) where activity_id = a.id;
  end if;

  -- Requesters/guests are notified through Realtime on their own (RLS-scoped) join_requests rows.
  update public.join_requests set updated_at = now() where activity_id = a.id and status in ('pending', 'accepted');
end $$;

create or replace function public.cancel_activity(p_activity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.activities;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into a from public.activities where id = p_activity_id for update;
  if not found or a.creator_id <> v_uid then raise exception 'not_found'; end if;
  if a.status <> 'active' then return; end if;
  update public.activities set status = 'cancelled' where id = a.id;
  update public.join_requests set status = 'cancelled' where activity_id = a.id and status = 'pending';
  update public.join_requests set updated_at = now() where activity_id = a.id and status = 'accepted';   -- notify guests
end $$;

-- Housekeeping for pg_cron or a scheduled Edge Function (service role only).
create or replace function public.mark_completed_activities()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  update public.activities set status = 'completed' where status = 'active' and end_time <= now();
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Join requests
-- ---------------------------------------------------------------------------
create or replace function public.request_to_join(p_activity_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := private.require_ready();
  a public.activities;
  v_id uuid;
begin
  select * into a from public.activities where id = p_activity_id;
  if not found or a.visibility <> 'public' or private.blocked_with(a.creator_id) then raise exception 'not_found'; end if;
  if a.creator_id = v_uid then raise exception 'own_activity'; end if;
  if a.status <> 'active' or a.end_time <= now() then raise exception 'activity_closed'; end if;
  if exists (select 1 from public.join_requests where activity_id = a.id and requester_id = v_uid and status = 'declined') then
    raise exception 'request_declined';
  end if;
  if (select count(*) from public.join_requests where activity_id = a.id and status = 'accepted') >= a.max_participants then
    raise exception 'activity_full';
  end if;
  begin
    insert into public.join_requests (activity_id, requester_id) values (a.id, v_uid) returning id into v_id;
  exception when unique_violation then
    raise exception 'already_requested';
  end;
  return v_id;
end $$;

create or replace function public.cancel_join_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.join_requests set status = 'cancelled'
  where id = p_request_id and requester_id = auth.uid() and status = 'pending';
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.leave_activity(p_activity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.join_requests set status = 'cancelled'
  where activity_id = p_activity_id and requester_id = auth.uid() and status = 'accepted';
  if not found then raise exception 'not_found'; end if;
end $$;

-- Host accepts or declines. The activity row is locked first, so concurrent approvals are serialised and
-- can never push the accepted count above max_participants.
create or replace function public.respond_to_join_request(p_request_id uuid, p_accept boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r public.join_requests;
  a public.activities;
  v_conversation uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into r from public.join_requests where id = p_request_id;
  if not found then raise exception 'not_found'; end if;

  select * into a from public.activities where id = r.activity_id for update;      -- serialise per activity
  if a.creator_id <> v_uid then raise exception 'not_found'; end if;
  select * into r from public.join_requests where id = p_request_id for update;      -- re-read under the lock
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if private.blocked_with(r.requester_id) then raise exception 'blocked'; end if;
  if a.status <> 'active' or a.end_time <= now() then raise exception 'activity_closed'; end if;

  if not p_accept then
    update public.join_requests set status = 'declined' where id = r.id;
    return 'declined';
  end if;

  if (select count(*) from public.join_requests where activity_id = a.id and status = 'accepted') >= a.max_participants then
    raise exception 'activity_full';
  end if;
  update public.join_requests set status = 'accepted' where id = r.id;

  -- Open (or re-use) the 1:1 conversation between the host and this guest.
  select c.id into v_conversation
  from public.conversations c
  where c.activity_id = a.id
    and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = a.creator_id)
    and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = r.requester_id)
  limit 1;
  if v_conversation is null then
    insert into public.conversations (activity_id) values (a.id) returning id into v_conversation;
    insert into public.conversation_participants (conversation_id, user_id)
    values (v_conversation, a.creator_id), (v_conversation, r.requester_id);
  end if;
  return 'accepted';
end $$;

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------
create or replace function public.block_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_user_id = v_uid then raise exception 'not_allowed'; end if;
  select display_name into v_name from public.profiles where id = p_user_id;
  if not found then raise exception 'not_found'; end if;

  insert into public.user_blocks (blocker_id, blocked_id, blocked_display_name)
  values (v_uid, p_user_id, v_name) on conflict do nothing;

  -- Sever live relationships both ways: requests on each other's activities.
  update public.join_requests r set status = 'cancelled'
  where r.status in ('pending', 'accepted')
    and exists (select 1 from public.activities a
                where a.id = r.activity_id
                  and ((a.creator_id = v_uid and r.requester_id = p_user_id)
                    or (a.creator_id = p_user_id and r.requester_id = v_uid)));
end $$;

create or replace function public.unblock_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.user_blocks where blocker_id = auth.uid() and blocked_id = p_user_id;
end $$;

-- ---------------------------------------------------------------------------
-- Discovery (PostGIS). All three return PUBLIC, approximate data only.
-- ---------------------------------------------------------------------------

-- Public live activities whose approximate location intersects the visible map rectangle.
-- "Today"/"Tomorrow" are expressed by the client as an overlap window [p_from, p_to].
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
  if p_type is not null and p_type not in ('walk', 'cowork') then raise exception 'invalid_type'; end if;
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
      union all
      select a.id, a.start_time from public.activities a
      join public.cowork_locations c on c.activity_id = a.id
      where a.visibility = 'public' and a.status = 'active' and a.end_time > v_from
        and (p_to is null or a.start_time < p_to)
        and (p_type is null or a.type = p_type)
        and ST_Intersects(c.public_point, v_env)
        and not private.blocked_with(a.creator_id)
    ) u
    order by u.start_time, u.id
    limit v_limit offset v_offset
  ) s;

  return query select * from private.cards_for(v_ids);
end $$;

-- Public live activities within `p_radius_m` metres of a point, nearest first.
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
  if p_type is not null and p_type not in ('walk', 'cowork') then raise exception 'invalid_type'; end if;
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
      union all
      select a.id, ST_Distance(c.public_point, v_pt) from public.activities a
      join public.cowork_locations c on c.activity_id = a.id
      where a.visibility = 'public' and a.status = 'active' and a.end_time > now()
        and (p_type is null or a.type = p_type)
        and ST_DWithin(c.public_point, v_pt, p_radius_m)
        and not private.blocked_with(a.creator_id)
    ) u
    order by u.dist, u.id
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) s;

  return query select * from private.cards_for(v_ids);
end $$;

-- Everything the user hosts or has asked to join (any status), most recent first. Private plans included for their creator.
create or replace function public.list_my_activities(p_limit integer default 200)
returns setof public.activity_card
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_ids uuid[];
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select coalesce(array_agg(s.id order by s.start_time desc, s.id), '{}') into v_ids from (
    select a.id, a.start_time from public.activities a
    where a.end_time > now() - interval '90 days'
      and not private.blocked_with(a.creator_id)
      and (a.creator_id = v_uid
           or exists (select 1 from public.join_requests r where r.activity_id = a.id and r.requester_id = v_uid))
    order by a.start_time desc, a.id
    limit least(greatest(coalesce(p_limit, 200), 1), 300)
  ) s;
  return query select * from private.cards_for(v_ids);
end $$;

-- Precise details, ONLY for the creator and accepted guests (and never across a block).
create or replace function public.get_private_activity_details(p_activity_ids uuid[])
returns table (activity_id uuid, type text,
               start_lng double precision, start_lat double precision, end_lng double precision, end_lat double precision,
               route_coordinates jsonb, cafe_name text, address text, meeting_details text)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select a.id, a.type,
           ST_X(w.start_coordinates::geometry), ST_Y(w.start_coordinates::geometry),
           ST_X(w.end_coordinates::geometry), ST_Y(w.end_coordinates::geometry),
           (ST_AsGeoJSON(w.route_geometry::geometry)::jsonb) -> 'coordinates',
           null::text, null::text, w.meeting_details
    from public.activities a join public.walk_routes w on w.activity_id = a.id
    where a.id = any (p_activity_ids) and not private.blocked_with(a.creator_id)
      and (a.creator_id = auth.uid() or private.is_accepted_guest(a.id))
    union all
    select a.id, a.type,
           c.longitude, c.latitude, null::double precision, null::double precision,
           null::jsonb, c.cafe_name, c.address, c.meeting_details
    from public.activities a join public.cowork_locations c on c.activity_id = a.id
    where a.id = any (p_activity_ids) and not private.blocked_with(a.creator_id)
      and (a.creator_id = auth.uid() or private.is_accepted_guest(a.id));
end $$;

-- ---------------------------------------------------------------------------
-- Function privileges: nothing is callable by `anon`/PUBLIC; signed-in users get the app RPCs only.
-- ---------------------------------------------------------------------------
alter default privileges in schema public revoke execute on functions from public, anon;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not in ('set_updated_at', 'handle_new_user', 'mark_completed_activities') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
-- NOTE: re-run this grant block (or add explicit grants) when adding new public functions.
