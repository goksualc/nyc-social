-- Along · migration 12 — "Where are you walking?": find public walks along a searched route (PostGIS, server-side)
--
-- The app sends the walking route MapKit calculated (a list of [lng, lat] points). Everything else happens here:
-- candidates are found with the spatial index, and every number returned is measured from geometry.
--
-- Matching uses each walk's PUBLIC geometry (the snapped, approximate line already shown to everyone). Exact routes are
-- never touched. Hidden (legacy private) walks and blocked organizers are excluded, and an anonymous organizer stays
-- masked because results come from private.cards_for.
--
-- Reported per walk (nothing is estimated by the client):
--   overlap_pct         share of the WALK's own length that runs inside the corridor around the searched route (0–1)
--   route_distance_m    closest distance between the walk's line and the searched route, in metres
--   direction_diff_deg  angle between the two routes' start→end directions (0 = same direction, 180 = opposite)
--   starts_near         the walk starts within the corridor of where the search starts
--   ends_near           the walk ends within the corridor of where the search ends
--   score               ranking: 40% overlap (scaled down when the walk heads the opposite way), 20% closeness,
--                       15% direction, 15% time fit, 10% open spots
--
-- Additive; does not modify earlier migrations. Run after migration 11.

create or replace function public.search_walks_along_route(
  p_route       jsonb,
  p_corridor_m  double precision default 500,
  p_from        timestamptz default null,
  p_to          timestamptz default null,
  p_when        timestamptz default null,
  p_mode        text default null,
  p_limit       integer default 30)
returns table (
  card               public.activity_card,
  overlap_pct        double precision,
  route_distance_m   double precision,
  direction_diff_deg double precision,
  starts_near        boolean,
  ends_near          boolean,
  score              double precision)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_uid      uuid := auth.uid();
  v_route    geography;
  v_geom     geometry;
  v_buffer   geometry;
  v_start    geography;
  v_end      geography;
  v_az       double precision;
  v_from     timestamptz := greatest(now(), coalesce(p_from, now()));
  v_corr     double precision := least(greatest(coalesce(p_corridor_m, 500), 50), 2000);
  v_limit    integer := least(greatest(coalesce(p_limit, 30), 1), 60);
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_mode is not null and p_mode not in ('just_walk', 'overthink') then raise exception 'invalid_walk_mode'; end if;
  if p_route is null or jsonb_typeof(p_route) <> 'array' or jsonb_array_length(p_route) not between 2 and 1000 then
    raise exception 'invalid_route';
  end if;
  if exists (select 1 from jsonb_array_elements(p_route) e
             where jsonb_typeof(e.value) <> 'array' or jsonb_array_length(e.value) < 2
                or not private.is_near_manhattan((e.value ->> 0)::double precision, (e.value ->> 1)::double precision)) then
    raise exception 'outside_manhattan';
  end if;

  select ST_MakeLine(array(
           select ST_SetSRID(ST_MakePoint((e.value ->> 0)::double precision, (e.value ->> 1)::double precision), 4326)
           from jsonb_array_elements(p_route) with ordinality as e(value, ord) order by e.ord))::geography
    into v_route;
  if v_route is null then raise exception 'invalid_route'; end if;
  v_geom   := v_route::geometry;
  v_buffer := ST_Buffer(v_route, v_corr)::geometry;
  v_start  := ST_StartPoint(v_geom)::geography;
  v_end    := ST_EndPoint(v_geom)::geography;
  v_az     := ST_Azimuth(ST_StartPoint(v_geom), ST_EndPoint(v_geom));

  return query
  with cand as (
    select a.id, a.start_time, a.max_participants,
           w.public_route_geometry as line, w.public_start_point as sp, w.public_end_point as ep,
           (select count(*) from public.join_requests r where r.activity_id = a.id and r.status = 'accepted') as going
    from public.activities a
    join public.walk_routes w on w.activity_id = a.id
    where a.visibility = 'public' and a.status = 'active' and a.end_time > v_from
      and (p_to is null or a.start_time < p_to)
      and (p_mode is null or w.walk_mode = p_mode)
      and ST_DWithin(w.public_route_geometry, v_route, v_corr)              -- uses walk_routes_public_route_gix
      and not private.blocked_with(a.creator_id)
      and a.creator_id <> v_uid
  ), measured as (
    select c.*,
           case when ST_Length(c.line) > 0
                then least(ST_Length(ST_Intersection(c.line::geometry, v_buffer)::geography) / ST_Length(c.line), 1.0)
                else case when ST_DWithin(c.sp, v_route, v_corr) then 1.0 else 0.0 end end as overlap,
           ST_Distance(c.line, v_route) as dist,
           case when ST_Distance(c.sp, c.ep) > 1
                then degrees(least(abs(v_az - ST_Azimuth(c.sp::geometry, c.ep::geometry)),
                                   2 * pi() - abs(v_az - ST_Azimuth(c.sp::geometry, c.ep::geometry))))
                end as dir_diff,
           ST_DWithin(c.sp, v_start, v_corr) as s_near,
           ST_DWithin(c.ep, v_end, v_corr) as e_near
    from cand c
  )
  select k,
         m.overlap, m.dist, m.dir_diff, m.s_near, m.e_near,
         0.40 * m.overlap * (case when m.dir_diff is null then 1.0 else 0.35 + 0.65 * greatest(cos(radians(m.dir_diff)), 0) end)
         + 0.20 * (1 - least(m.dist / v_corr, 1))
         + 0.15 * (case when m.dir_diff is null then 0.5 else greatest(cos(radians(m.dir_diff)), 0) end)
         + 0.15 * (case when p_when is null then 0.5 else exp(-abs(extract(epoch from (m.start_time - p_when)) / 3600.0) / 3.0) end)
         + 0.10 * (case when m.max_participants - m.going > 0 then 1 else 0 end) as sc
  from measured m
  cross join lateral private.cards_for(array[m.id]) k
  order by sc desc, m.start_time, m.id
  limit v_limit;
end $$;

revoke all on function public.search_walks_along_route(jsonb, double precision, timestamptz, timestamptz, timestamptz, text, integer) from public, anon;
grant execute on function public.search_walks_along_route(jsonb, double precision, timestamptz, timestamptz, timestamptz, text, integer) to authenticated;
