\set ON_ERROR_STOP on
select t.root();
truncate t.log;
insert into auth.users (id, email) values ('a1000000-0000-0000-0000-00000000000a', 'alice@test'), ('b1000000-0000-0000-0000-00000000000b', 'bob@test');
do $$ begin
  perform t.login('a1000000-0000-0000-0000-00000000000a'); perform public.complete_profile('Alice', '', array[]::text[], array['walking_buddies'], true);
  perform t.login('b1000000-0000-0000-0000-00000000000b'); perform public.complete_profile('Bob', '', array[]::text[], array['walking_buddies'], true);
  perform t.root();
end $$;

-- boundary checks: inside the city
select t.check('Times Square (Manhattan) is in', private.is_in_nyc(-73.9855, 40.7580));
select t.check('Prospect Park (Brooklyn) is in', private.is_in_nyc(-73.9690, 40.6602));
select t.check('Coney Island (Brooklyn) is in', private.is_in_nyc(-73.9707, 40.5755));
select t.check('Flushing Meadows (Queens) is in', private.is_in_nyc(-73.8408, 40.7466));
select t.check('Rockaway Beach (Queens) is in', private.is_in_nyc(-73.8160, 40.5834));
select t.check('Yankee Stadium (Bronx) is in', private.is_in_nyc(-73.9262, 40.8296));
select t.check('Pelham Bay Park (Bronx) is in', private.is_in_nyc(-73.8280, 40.8528));
select t.check('St. George ferry (Staten Island) is in', private.is_in_nyc(-74.0735, 40.6437));
select t.check('Tottenville (Staten Island) is in', private.is_in_nyc(-74.2430, 40.5080));
-- and outside it
select t.check('Jersey City is out', not private.is_in_nyc(-74.0431, 40.7282));
select t.check('Hoboken is out', not private.is_in_nyc(-74.0324, 40.7440));
select t.check('Yonkers is out', not private.is_in_nyc(-73.8987, 40.9312));
select t.check('Mount Vernon is out', not private.is_in_nyc(-73.8370, 40.9126));
select t.check('Hempstead (Nassau) is out', not private.is_in_nyc(-73.6187, 40.7062));
select t.check('Newark is out', not private.is_in_nyc(-74.1724, 40.7357));
select t.check('mid-Atlantic is out', not private.is_in_nyc(-73.9000, 40.3000));
select t.check('the old helper names now mean the whole city', private.is_in_manhattan(-73.9690, 40.6602) and private.is_near_manhattan(-73.9690, 40.6602));

-- creating, discovering and joining across boroughs
select t.login('a1000000-0000-0000-0000-00000000000a');
create or replace function pg_temp.mk(p_title text, p_slng float8, p_slat float8, p_elng float8, p_elat float8)
returns uuid language sql as $$
  select public.create_walk(p_title := p_title, p_description := '', p_start_time := now() + interval '3 hours', p_end_time := now() + interval '4 hours',
    p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'A', p_end_label := 'B',
    p_start_lng := p_slng, p_start_lat := p_slat, p_end_lng := p_elng, p_end_lat := p_elat)
$$;
select pg_temp.mk('Brooklyn: Prospect Park to Park Slope', -73.9690, 40.6602, -73.9814, 40.6710);
select pg_temp.mk('Queens: Astoria Park to LIC', -73.9235, 40.7644, -73.9485, 40.7447);
select pg_temp.mk('Bronx: Fordham to Bronx Zoo', -73.8900, 40.8610, -73.8770, 40.8506);
select pg_temp.mk('Staten Island: St. George to Snug Harbor', -74.0735, 40.6437, -74.1020, 40.6445);
select pg_temp.mk('Cross-borough: Williamsburg Bridge to Lower East Side', -73.9571, 40.7081, -73.9843, 40.7150);
select pg_temp.mk('Cross-borough: Brooklyn Bridge Park to City Hall', -73.9965, 40.7016, -74.0060, 40.7127);
do $$ begin
  begin perform pg_temp.mk('Jersey City', -74.0431, 40.7282, -73.9855, 40.7580); raise exception 'accepted a New Jersey start';
  exception when others then if sqlerrm <> 'outside_manhattan' then raise; end if; end;
  begin perform pg_temp.mk('Ends in Yonkers', -73.9262, 40.8296, -73.8987, 40.9312); raise exception 'accepted a Westchester end';
  exception when others then if sqlerrm <> 'outside_manhattan' then raise; end if; end;
end $$;
select t.check('both a New Jersey start and a Westchester end are refused', true);

select t.login('b1000000-0000-0000-0000-00000000000b');
create temp table seen as select (c).title as title, (c).public_area as area, (c).id as id
  from public.discover_activities(-74.28, 40.47, -73.68, 40.95, 'walk', null, null, 50, 0) c;
grant all on seen to public;
select t.check('all six new walks are discoverable in one NYC-wide window', (select count(*) from seen) = 6, (select string_agg(title, ' | ') from seen));
select t.check('areas come from the right borough neighbourhoods',
  (select area from seen where title like 'Brooklyn:%') in ('Prospect Park', 'Park Slope')
  and (select area from seen where title like 'Queens:%') in ('Astoria', 'Long Island City')
  and (select area from seen where title like 'Bronx:%') in ('Fordham', 'Belmont', 'Bronx Zoo')
  and (select area from seen where title like 'Staten%') in ('St. George', 'Snug Harbor'),
  (select string_agg(area, ', ') from seen));
select t.check('a Brooklyn-only box returns only Brooklyn-side walks', (select count(*) from public.discover_activities(-74.05, 40.57, -73.85, 40.70, 'walk', null, null, 50, 0) c where (c).title like 'Brooklyn:%') = 1);
select t.check('a Bronx-only box does not return the Brooklyn walk', (select count(*) from public.discover_activities(-73.95, 40.80, -73.75, 40.92, 'walk', null, null, 50, 0) c where (c).title like 'Brooklyn:%') = 0);
-- joining a Staten Island walk
select public.request_to_join((select id from seen where title like 'Staten%'));
select t.check('Bob can request to join a Staten Island walk', (select count(*) from public.join_requests where status = 'pending') = 1);
-- route search across boroughs
select t.check('a Williamsburg → Lower East Side route search finds the cross-borough walk',
  exists (select 1 from public.search_walks_along_route('[[-73.9571,40.7081],[-73.9700,40.7115],[-73.9843,40.7150]]'::jsonb) r where (r.card).title like 'Cross-borough: Williamsburg%'));
select * from t.log where not ok order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
