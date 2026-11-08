\set ON_ERROR_STOP on
select t.root();
truncate t.log;
insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-00000000000a', 'alice@test'), ('b1000000-0000-0000-0000-00000000000b', 'bob@test'), ('c1000000-0000-0000-0000-00000000000c', 'carol@test');
do $$
declare u record;
begin
  for u in select * from (values ('a1000000-0000-0000-0000-00000000000a'::uuid, 'Alice'), ('b1000000-0000-0000-0000-00000000000b'::uuid, 'Bob'),
                                 ('c1000000-0000-0000-0000-00000000000c'::uuid, 'Carol')) v(id, n) loop
    perform t.login(u.id); perform public.complete_profile(u.n, '', array[]::text[], array['walking_buddies'], true);
  end loop;
  perform t.root();
end $$;

-- Walks by Alice (searcher is Bob): a mix of matching, near, opposite and far-away routes
select t.login('a1000000-0000-0000-0000-00000000000a');
create or replace function pg_temp.mk(p_title text, p_hours int, p_slng float8, p_slat float8, p_elng float8, p_elat float8, p_prompt text default null, p_anon boolean default false)
returns uuid language sql as $$
  select public.create_walk(p_title := p_title, p_description := '', p_start_time := now() + make_interval(hours => p_hours), p_end_time := now() + make_interval(hours => p_hours + 1),
    p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'A', p_end_label := 'B',
    p_start_lng := p_slng, p_start_lat := p_slat, p_end_lng := p_elng, p_end_lat := p_elat, p_mind_prompt := p_prompt,
    p_anonymous_host := p_anon, p_host_interests := array['Coffee'])
$$;
select pg_temp.mk('W1 Union Sq to Bryant', 3, -73.9911, 40.7359, -73.9832, 40.7536);
select pg_temp.mk('W2 Washington Sq to Midtown', 4, -73.9973, 40.7308, -73.9855, 40.7580, 'Work, mostly');
select pg_temp.mk('W3 Chelsea to Bryant', 26, -74.0010, 40.7440, -73.9832, 40.7536);
select pg_temp.mk('W4 Harlem loop', 3, -73.9500, 40.8100, -73.9450, 40.8200);
select pg_temp.mk('W5 Bryant to West Village (opposite)', 3, -73.9832, 40.7536, -74.0030, 40.7340);
select pg_temp.mk('W6 Anonymous Union Sq to Bryant', 5, -73.9911, 40.7359, -73.9832, 40.7536, null, true);
select pg_temp.mk('W7 Exact match West Village to Bryant', 3, -74.0030, 40.7340, -73.9832, 40.7536);
select t.root();
-- A legacy hidden walk right on the route must never be returned
update public.activities set visibility = 'private', host_anonymous = false where title = 'W1 Union Sq to Bryant';
select t.login('a1000000-0000-0000-0000-00000000000a');
select pg_temp.mk('W1b Union Sq to Bryant (public)', 3, -73.9911, 40.7359, -73.9832, 40.7536);

select t.login('b1000000-0000-0000-0000-00000000000b');
create temp table res as
  select (r.card).title as title, (r.card).creator_id as creator_id, (r.card).host_name as host_name, r.overlap_pct, r.route_distance_m, r.direction_diff_deg,
         r.starts_near, r.ends_near, r.score
  from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9980,40.7390],[-73.9930,40.7440],[-73.9880,40.7490],[-73.9832,40.7536]]'::jsonb) r;
grant all on res to public;
select t.check('returns real matches', (select count(*) from res) >= 4, (select string_agg(title, ' | ' order by score desc) from res));
select t.check('a far-away walk (Harlem) is NOT returned', (select count(*) from res where title like 'W4%') = 0);
select t.check('a hidden legacy private walk is NOT returned', (select count(*) from res where title = 'W1 Union Sq to Bryant') = 0);
select t.check('the public twin of it IS returned', (select count(*) from res where title like 'W1b%') = 1);
select t.check('the walk identical to the search ranks first', (select title from res order by score desc limit 1) like 'W7%');
select t.check('identical walk overlaps ~100%', (select overlap_pct from res where title like 'W7%') > 0.95);
select t.check('identical walk has ~0 distance and same direction', (select route_distance_m < 50 and direction_diff_deg < 10 from res where title like 'W7%'));
select t.check('identical walk starts and ends near the searched ones', (select starts_near and ends_near from res where title like 'W7%'));
select t.check('Union Sq → Bryant overlaps only part of the corridor but a lot', (select overlap_pct between 0.5 and 1 from res where title like 'W1b%'));
select t.check('Union Sq → Bryant does not start near the search start but ends near its end', (select not starts_near and ends_near from res where title like 'W1b%'));
select t.check('opposite-direction walk is flagged ~180°', (select direction_diff_deg > 150 from res where title like 'W5%'));
select t.check('and ranks below the same-direction walk', (select score from res where title like 'W5%') < (select score from res where title like 'W1b%'));
select t.check('every overlap is a real fraction 0..1', (select bool_and(overlap_pct between 0 and 1) from res));
select t.check('scores are ordered best first', (select bool_and(s >= next_s) from (select score as s, lead(score) over (order by score desc, title) as next_s from res) q where next_s is not null));
select t.check('the anonymous walk is found but masked', (select creator_id like 'anon:%' and host_name = 'Anonymous Walker' from res where title like 'W6%'));
select t.check('the organizer id is nowhere in the results', position('a1000000-0000-0000-0000-00000000000a' in (select jsonb_agg(to_jsonb(r))::text from res r where title not like 'W1b%' and title not like 'W7%' and title not like 'W2%' and title not like 'W3%' and title not like 'W5%')) = 0);

-- filters
select t.check('the optional prompt travels with the card', (select count(*) from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb) r where (r.card).mind_prompt = 'Work, mostly') = 1);
create temp table res_time as select (r.card).title as title from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb, 500, now() + interval '24 hours', now() + interval '30 hours') r;
grant all on res_time to public;
select t.check('date window keeps only walks in it (tomorrow)', (select count(*) from res_time) = 1 and (select title from res_time limit 1) like 'W3%');
create temp table res_narrow as select (r.card).title as title from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb, 50) r;
grant all on res_narrow to public;
select t.check('a narrower corridor returns fewer walks', (select count(*) from res_narrow) < (select count(*) from res));
select t.check('limit is respected', (select count(*) from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb, 2000, null, null, null, null, 2)) = 2);

-- validation
select t.expect_error('route must have 2+ points', $$select * from public.search_walks_along_route('[[-74.0,40.7]]'::jsonb)$$, 'invalid_route');
select t.expect_error('route outside NYC rejected (New Jersey)', $$select * from public.search_walks_along_route('[[-74.20,40.72],[-74.10,40.72]]'::jsonb)$$, 'outside_manhattan');
select t.anon();
select t.expect_error('anon cannot search', $$select * from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb)$$, 'permission denied');

-- blocked organizers disappear; the searcher's own walks are not suggested
select t.login('b1000000-0000-0000-0000-00000000000b');
select public.block_user('a1000000-0000-0000-0000-00000000000a');
select t.check('blocked organizer: no results at all', (select count(*) from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb)) = 0);
select t.login('a1000000-0000-0000-0000-00000000000a');
select t.check('organizer is never shown their own walks', (select count(*) from public.search_walks_along_route('[[-74.0030,40.7340],[-73.9832,40.7536]]'::jsonb)) = 0);

-- spatial index is used for the candidate search
select t.root();
select t.check('GiST index exists on the public route geometry', exists (select 1 from pg_indexes where indexname = 'walk_routes_public_route_gix'));

select * from t.log where not ok order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
