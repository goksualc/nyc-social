\set ON_ERROR_STOP on
-- The exact reads and writes the iOS app makes for chats, after migration 11 locked the raw tables.
select t.root();
truncate t.log;
insert into auth.users (id, email) values ('a1000000-0000-0000-0000-00000000000a', 'alice@test'), ('b1000000-0000-0000-0000-00000000000b', 'bob@test');
do $$ begin
  perform t.login('a1000000-0000-0000-0000-00000000000a'); perform public.complete_profile('Alice', '', array[]::text[], array['walking_buddies'], true);
  perform t.login('b1000000-0000-0000-0000-00000000000b'); perform public.complete_profile('Bob', '', array[]::text[], array['walking_buddies'], true);
  perform t.root();
end $$;
select t.login('a1000000-0000-0000-0000-00000000000a');
create temp table ids as select public.create_walk(p_title := 'Anon walk', p_description := '', p_start_time := now() + interval '3 hours', p_end_time := now() + interval '4 hours',
  p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'A', p_end_label := 'B',
  p_start_lng := -73.9911, p_start_lat := 40.7359, p_end_lng := -73.9832, p_end_lat := 40.7536,
  p_anonymous_host := true, p_host_interests := array['Tech']) as walk;
grant all on ids to public;
select t.check('creating a Private Host walk works', (select walk from ids) is not null);
select t.check('and the app can read my plans afterwards', (select count(*) from public.list_my_activities()) = 1);
select t.expect_error('the OLD direct read of messages is refused (this was the "You can''t do that")', $$select id from public.messages limit 1$$, 'permission denied');
select t.expect_error('the OLD direct read of conversation_participants is refused', $$select user_id from public.conversation_participants limit 1$$, 'permission denied');
select t.check('the NEW read of conversations works', public.list_my_conversations() is not null);
select t.check('the NEW read of messages works', public.list_my_messages(null, null, 200) is not null);
select * from t.log where not ok order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
