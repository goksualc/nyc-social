\set ON_ERROR_STOP on
select t.root();
truncate t.log;
insert into auth.users (id, email) values ('a1000000-0000-0000-0000-00000000000a', 'alice@test'), ('b1000000-0000-0000-0000-00000000000b', 'bob@test');
do $$ begin
  perform t.login('a1000000-0000-0000-0000-00000000000a'); perform public.complete_profile('Alice', '', array[]::text[], array['walking_buddies'], true);
  perform t.login('b1000000-0000-0000-0000-00000000000b'); perform public.complete_profile('Bob', '', array[]::text[], array['walking_buddies'], true);
  perform t.root();
end $$;

select t.login('a1000000-0000-0000-0000-00000000000a');
create or replace function pg_temp.mk(p_title text, p_anon boolean, p_tags text[])
returns uuid language sql as $$
  select public.create_walk(p_title := p_title, p_description := '', p_start_time := now() + interval '3 hours', p_end_time := now() + interval '4 hours',
    p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'A', p_end_label := 'B',
    p_start_lng := -73.9911, p_start_lat := 40.7359, p_end_lng := -73.9832, p_end_lat := 40.7536,
    p_anonymous_host := p_anon, p_host_interests := p_tags)
$$;
select pg_temp.mk('Public with tags', false, array['Tech', 'Career']);
select pg_temp.mk('Private host with tags', true, array['Life', 'Random Thoughts', 'Psychology']);
select pg_temp.mk('Anonymous host, no tags', true, array[]::text[]);
select pg_temp.mk('Public no tags', false, array[]::text[]);

select t.login('b1000000-0000-0000-0000-00000000000b');
create temp table seen as
  select (c).title as title, (c).creator_id as creator_id, (c).host_name as host_name, (c).host_interests as tags, (c).host_anonymous as anon
  from public.discover_activities(-74.05, 40.70, -73.90, 40.78, 'walk', null, null, 50, 0) c;
grant all on seen to public;
select t.check('all four are discoverable', (select count(*) from seen) = 4);
select t.check('a public walk now returns its tags', (select tags from seen where title = 'Public with tags') = array['Tech','Career']);
select t.check('a public walk still shows its host', (select host_name from seen where title = 'Public with tags') = 'Alice' and (select not anon from seen where title = 'Public with tags'));
select t.check('a private-host walk shows tags but hides the host', (select tags from seen where title like 'Private host%') = array['Life','Random Thoughts','Psychology']
  and (select host_name = 'Anonymous Walker' and creator_id like 'anon:%' and anon from seen where title like 'Private host%'));
select t.check('an anonymous-host walk shows no extra details', (select cardinality(tags) = 0 and host_name = 'Anonymous Walker' from seen where title like 'Anonymous host%'));
select t.check('a walk with no tags returns none', (select cardinality(tags) = 0 from seen where title = 'Public no tags'));
select t.check('the organizer id never appears for hidden hosts', position('a1000000-0000-0000-0000-00000000000a' in (select jsonb_agg(to_jsonb(s))::text from seen s where anon)) = 0);
select t.login('a1000000-0000-0000-0000-00000000000a');
select t.expect_error('more than four tags is still refused', $$select pg_temp.mk('x', false, array['a','b','c','d','e'])$$, 'invalid_interests');
select * from t.log where not ok order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
