-- Along · migration 13 — one kind of walk
--
-- Along has a single activity type: a Walk. "Just Walk" and "Overthink Together" are no longer separate modes; overthinking
-- is simply what Along is for. A walk can carry one optional free-text prompt, "What's on your mind?".
--
-- Compatibility: nothing is dropped. `walk_mode`, `conversation_topic`, `custom_topic` and `conversation_preference` stay in
-- place (old rows, old clients, old tests), but nothing new writes them and no client reads them any more. Existing Overthink
-- walks keep what they said as their prompt.
--
-- Run after migration 12. Does not modify earlier migrations.

alter table public.walk_routes
  add column if not exists mind_prompt text check (char_length(mind_prompt) between 1 and 140);

-- Existing walks: carry over whatever the host had written about the conversation.
update public.walk_routes
   set mind_prompt = left(coalesce(custom_topic,
         case conversation_topic when 'life_lately' then 'Life lately' when 'career' then 'Career' when 'relationships' then 'Relationships'
                                 when 'existential' then 'Existential thoughts' when 'random' then 'Random thoughts' when 'anything' then 'Anything, really' end), 140)
 where mind_prompt is null and walk_mode = 'overthink' and (custom_topic is not null or conversation_topic is not null);

alter type public.activity_card add attribute mind_prompt text;

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
    case when a.host_anonymous and a.host_revealed_at is null then a.host_interests else '{}'::text[] end,
    w.mind_prompt
  from public.activities a
  join public.profiles p on p.id = a.creator_id
  left join public.walk_routes w on w.activity_id = a.id
  left join public.cowork_locations c on c.activity_id = a.id
  where a.id = any (p_ids)
  order by array_position(p_ids, a.id)
$$;

drop function if exists public.create_walk(
  text, text, timestamptz, timestamptz, integer, text, text, text, text,
  double precision, double precision, double precision, double precision, jsonb, text,
  text, text, text, text, boolean, text[]);

create or replace function public.create_walk(
  p_title text, p_description text, p_start_time timestamptz, p_end_time timestamptz,
  p_max_participants integer, p_visibility text, p_pace text,
  p_start_label text, p_end_label text,
  p_start_lng double precision, p_start_lat double precision,
  p_end_lng double precision, p_end_lat double precision,
  p_route jsonb default null, p_meeting_details text default '',
  p_anonymous_host boolean default false, p_host_interests text[] default '{}',
  p_mind_prompt text default null)
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
  p_mind_prompt := nullif(btrim(coalesce(p_mind_prompt, '')), '');
  if p_mind_prompt is not null and char_length(p_mind_prompt) > 140 then raise exception 'invalid_description'; end if;
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
                                  mind_prompt)
  values (v_id, p_pace,
          private.safe_label(p_start_label, private.nearest_neighborhood(v_start)),
          private.safe_label(p_end_label, private.nearest_neighborhood(v_end)),
          v_area, v_pstart, v_pend,
          ST_MakeLine(v_pstart::geometry, v_pend::geometry)::geography,   -- degenerate when both snap to one cell
          v_start, v_end, v_route, greatest(round(ST_Length(v_route))::integer, 50),
          btrim(coalesce(p_meeting_details, '')),
          p_mind_prompt);
  return v_id;
exception when check_violation or numeric_value_out_of_range then
  raise exception 'invalid_route';
end $$;

revoke all on function public.create_walk(text, text, timestamptz, timestamptz, integer, text, text, text, text, double precision, double precision,
  double precision, double precision, jsonb, text, boolean, text[], text) from public, anon;
grant execute on function public.create_walk(text, text, timestamptz, timestamptz, integer, text, text, text, text, double precision, double precision,
  double precision, double precision, jsonb, text, boolean, text[], text) to authenticated;
