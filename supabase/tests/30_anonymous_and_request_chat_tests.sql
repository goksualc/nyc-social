\set ON_ERROR_STOP on
select t.root();

-- Users: alice (organizer), bob (applicant), carol (stranger / second applicant), dave (extra)
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-00000000000a', 'alice@test', '{"full_name":"Alice Anderson"}'),
  ('b0000000-0000-0000-0000-00000000000b', 'bob@test',   '{"full_name":"Bob Brown"}'),
  ('c0000000-0000-0000-0000-00000000000c', 'carol@test', '{}'),
  ('d0000000-0000-0000-0000-00000000000d', 'dave@test',  '{}');
do $$
declare u record;
begin
  for u in select * from (values
      ('a0000000-0000-0000-0000-00000000000a'::uuid, 'Alice'), ('b0000000-0000-0000-0000-00000000000b'::uuid, 'Bob'),
      ('c0000000-0000-0000-0000-00000000000c'::uuid, 'Carol'), ('d0000000-0000-0000-0000-00000000000d'::uuid, 'Dave')) v(id, n) loop
    perform t.login(u.id);
    perform public.complete_profile(u.n, 'Hi, I am ' || u.n, array[]::text[], array['walking_buddies'], true);
    update public.profiles set hobbies = array['Philosophy', 'Coffee', 'Technology'], instagram_username = lower(u.n) || '_ig',
           occupation = 'Secret job of ' || u.n where id = u.id;
  end loop;
  perform t.root();
end $$;

-- ===== 1. anonymous walk is public on the map, identity hidden =============
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('create_walk with an anonymous organizer works', public.create_walk(
  p_title := 'Overthinking Our Careers', p_description := 'Come walk', p_start_time := now() + interval '3 hours', p_end_time := now() + interval '4 hours',
  p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'West Village', p_end_label := 'Bryant Park',
  p_start_lng := -74.0030, p_start_lat := 40.7340, p_end_lng := -73.9832, p_end_lat := 40.7536,
  p_mind_prompt := 'Career, honestly',
  p_anonymous_host := true, p_host_interests := array['Technology', 'Philosophy']) is not null);
create temp table ids as select id as walk from public.activities where title = 'Overthinking Our Careers';
grant all on ids to public;
grant all on ids to authenticated;
select t.root();
select t.check('the walk is stored as PUBLIC (discoverable)', (select visibility from public.activities where id = (select walk from ids)) = 'public');
select t.check('and flagged anonymous', (select host_anonymous from public.activities where id = (select walk from ids)));
select t.check('interests chosen are stored', (select host_interests from public.activities where id = (select walk from ids)) = array['Technology','Philosophy']);

select t.login('c0000000-0000-0000-0000-00000000000c');
create temp table seen as select * from public.discover_activities(-74.05, 40.70, -73.90, 40.80);
grant all on seen to public;
grant all on seen to authenticated;
select t.check('stranger SEES the anonymous walk on the map', (select count(*) from seen where title = 'Overthinking Our Careers') = 1);
select t.check('organizer id is masked', (select creator_id from seen where title = 'Overthinking Our Careers') like 'anon:%');
select t.check('name is "Anonymous Walker"', (select host_name from seen where title = 'Overthinking Our Careers') = 'Anonymous Walker');
select t.check('no avatar', (select host_avatar_path from seen where title = 'Overthinking Our Careers') is null);
select t.check('only the chosen interests show', (select host_interests from seen where title = 'Overthinking Our Careers') = array['Technology','Philosophy']);
select t.check('card flags the host as anonymous', (select host_anonymous from seen where title = 'Overthinking Our Careers'));
select t.check('real user id appears NOWHERE in the public response',
  (select position('a0000000-0000-0000-0000-00000000000a' in (select jsonb_agg(to_jsonb(s))::text from seen s)) = 0));
select t.check('nor the organizer name', (select position('Alice' in (select jsonb_agg(to_jsonb(s))::text from seen s)) = 0));
select t.check('prompt, pace and spots are public', (select mind_prompt = 'Career, honestly' and pace = 'casual' and max_participants = 2 from seen limit 1));
select t.check('stranger cannot read the activity row (it carries creator_id)', t.scalar($$select count(*) from public.activities$$) = 0);

-- the organizer sees their own walk normally
select t.login('a0000000-0000-0000-0000-00000000000a');
create temp table mine as select * from public.list_my_activities();
grant all on mine to public;
select t.check('organizer sees the real creator id on their own card', (select creator_id from mine where title = 'Overthinking Our Careers') = 'a0000000-0000-0000-0000-00000000000a');
select t.check('organizer sees viewer_is_creator', (select viewer_is_creator from mine where title = 'Overthinking Our Careers'));
select t.check('organizer can read own activity row', t.scalar($$select count(*) from public.activities$$) = 1);

-- a plain public walk is fully visible
select public.create_walk(p_title := 'Open Walk', p_description := '', p_start_time := now() + interval '5 hours', p_end_time := now() + interval '6 hours',
  p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'Union Square', p_end_label := 'Chelsea',
  p_start_lng := -73.9911, p_start_lat := 40.7359, p_end_lng := -74.0010, p_end_lat := 40.7440);
select t.login('c0000000-0000-0000-0000-00000000000c');
create temp table seen2 as select * from public.discover_activities(-74.05, 40.70, -73.90, 40.80);
grant all on seen2 to public;
select t.check('a normal public walk still shows the organizer', (select host_name from seen2 where title = 'Open Walk') = 'Alice'
                                                              and (select creator_id from seen2 where title = 'Open Walk') = 'a0000000-0000-0000-0000-00000000000a');
select t.check('a normal public walk is not marked anonymous', not (select host_anonymous from seen2 where title = 'Open Walk'));

-- "private" in the old API now means: on the map, identity hidden
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.create_walk(p_title := 'Old API Private', p_description := '', p_start_time := now() + interval '7 hours', p_end_time := now() + interval '8 hours',
  p_max_participants := 2, p_visibility := 'private', p_pace := 'casual', p_start_label := 'Union Square', p_end_label := 'Chelsea',
  p_start_lng := -73.9911, p_start_lat := 40.7359, p_end_lng := -74.0010, p_end_lat := 40.7440);
select t.root();
select t.check('p_visibility=private is stored as public + anonymous, never hidden',
  (select visibility = 'public' and host_anonymous from public.activities where title = 'Old API Private'));
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.expect_error('too many interests rejected', $$select public.create_walk(p_title := 'x', p_description := '', p_start_time := now() + interval '7 hours', p_end_time := now() + interval '8 hours', p_max_participants := 2, p_visibility := 'public', p_pace := 'casual', p_start_label := 'a', p_end_label := 'b', p_start_lng := -73.9911, p_start_lat := 40.7359, p_end_lng := -74.0010, p_end_lat := 40.7440, p_anonymous_host := true, p_host_interests := array['a','b','c','d','e'])$$, 'invalid_interests');

-- ===== 2. legacy hidden walks stay hidden until the owner opts in ===========
select t.root();
update public.activities set visibility = 'private', host_anonymous = false where title = 'Old API Private';     -- simulate a pre-migration private walk
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('a legacy private walk is NOT discoverable', (select count(*) from public.discover_activities(-74.05, 40.70, -73.90, 40.80) where title = 'Old API Private') = 0);
select t.expect_error('a stranger cannot convert someone else''s walk', $$select public.make_walk_anonymous_public((select id from public.activities where title = 'Old API Private'))$$, 'not_found');
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.make_walk_anonymous_public((select id from public.activities where title = 'Old API Private'), array['Coffee']);
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('after the owner opts in it is discoverable, identity hidden',
  (select count(*) from public.discover_activities(-74.05, 40.70, -73.90, 40.80) where title = 'Old API Private' and creator_id like 'anon:%') = 1);

-- ===== 3. join request + pre-approval conversation =========================
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.check('applicant requests the anonymous walk', public.request_to_join((select walk from ids)) is not null);
create temp table req as select id as rid from public.join_requests where requester_id = auth.uid();
grant all on req to public;
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('organizer sees the pending request', t.scalar($$select count(*) from public.join_requests where status = 'pending' and requester_id = 'b0000000-0000-0000-0000-00000000000b'$$) = 1);
select t.root();
create temp table rq as select id as rid from public.join_requests where requester_id = 'b0000000-0000-0000-0000-00000000000b';
grant all on rq to public;

select t.login('b0000000-0000-0000-0000-00000000000b');
select t.expect_error('the applicant cannot start the conversation', format($$select public.start_request_conversation('%s')$$, (select rid from rq)), 'not_found');
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.expect_error('a stranger cannot start it either', format($$select public.start_request_conversation('%s')$$, (select rid from rq)), 'not_found');
select t.login('a0000000-0000-0000-0000-00000000000a');
create temp table conv as select public.start_request_conversation((select rid from rq)) as cid;
grant all on conv to public;
select t.check('organizer starts a conversation while the request is pending', (select cid from conv) is not null);
select t.check('starting again returns the SAME conversation (no duplicates)', public.start_request_conversation((select rid from rq)) = (select cid from conv));
select t.root();
select t.check('exactly one conversation exists for the request', (select count(*) from public.conversations where request_id = (select rid from rq)) = 1);
select t.check('the request is still pending (messaging never approves)', (select status from public.join_requests where id = (select rid from rq)) = 'pending');

select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('organizer sends first message', public.send_message((select cid from conv), 'Hey! Have you walked around this area before?') is not null);
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.check('applicant can reply while pending', public.send_message((select cid from conv), 'Not really, I''m new to NYC!') is not null);

-- ===== 4. nothing identifies the anonymous organizer in chat =================
create temp table b_convs as select public.list_my_conversations() as j;
grant all on b_convs to public;
create temp table b_msgs  as select public.list_my_messages() as j;
select t.check('applicant sees the conversation', jsonb_array_length((select j from b_convs)) = 1);
select t.check('organizer id absent from conversation payload', position('a0000000-0000-0000-0000-00000000000a' in (select j::text from b_convs)) = 0);
select t.check('participant list shows an anon alias', (select j::text from b_convs) like '%anon:%');
select t.check('organizer id absent from message payload', position('a0000000-0000-0000-0000-00000000000a' in (select j::text from b_msgs)) = 0);
select t.check('organizer messages carry the alias as sender', (select j::text from b_msgs) like '%anon:%');
select t.check('applicant sees both messages', jsonb_array_length((select j from b_msgs)) = 2);
select t.expect_error('applicant cannot read messages table directly', $$select * from public.messages$$, 'permission denied');
select t.expect_error('applicant cannot read participants directly', $$select * from public.conversation_participants$$, 'permission denied');
select t.expect_error('applicant cannot insert messages directly', format($$insert into public.messages (conversation_id, content) values ('%s', 'x')$$, (select cid from conv)), 'permission denied');

select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('stranger sees no conversations', jsonb_array_length(public.list_my_conversations()) = 0);
select t.check('stranger sees no messages', jsonb_array_length(public.list_my_messages()) = 0);
select t.check('stranger cannot read a specific conversation either', jsonb_array_length(public.list_my_messages((select cid from conv))) = 0);
select t.expect_error('stranger cannot send into it', format($$select public.send_message('%s', 'hi')$$, (select cid from conv)), 'chat_closed');
select t.check('stranger cannot read the pings table rows', t.scalar($$select count(*) from public.chat_pings$$) = 0);

select t.login('b0000000-0000-0000-0000-00000000000b');
select t.check('applicant sees pings only for their conversation', t.scalar($$select count(*) from public.chat_pings$$) >= 1);
select t.check('pings carry no user ids', (select count(*) from information_schema.columns where table_name = 'chat_pings' and (column_name ilike '%user%' or column_name ilike '%sender%')) = 0);

-- the organizer sees real ids (their own world)
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('organizer sees the applicant in their conversation', (select j::text from (select public.list_my_conversations() as j) x) like '%b0000000-0000-0000-0000-00000000000b%');

-- ===== 5. abuse protection ===================================================
select public.send_message((select cid from conv), 'm2');
select public.send_message((select cid from conv), 'm3');
select public.send_message((select cid from conv), 'm4');
select public.send_message((select cid from conv), 'm5');
select public.send_message((select cid from conv), 'm6');      -- the 5th message since the applicant last wrote: still allowed
select t.expect_error('organizer cannot flood an applicant who has not answered', format($$select public.send_message('%s', 'm7')$$, (select cid from conv)), 'rate_limited');

-- ===== 6. closing: decline / cancelled / expired =============================
select t.root();
create temp table rq2 as select id as rid from public.join_requests where requester_id = 'b0000000-0000-0000-0000-00000000000b';
grant all on rq2 to public;
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.respond_to_join_request((select rid from rq2), false);
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.expect_error('declined request closes the conversation', format($$select public.send_message('%s', 'hello?')$$, (select cid from conv)), 'chat_closed');
select t.check('history stays readable after it closes', jsonb_array_length(public.list_my_messages((select cid from conv))) >= 2);
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.expect_error('organizer cannot message after decline', format($$select public.send_message('%s', 'x')$$, (select cid from conv)), 'chat_closed');
select t.expect_error('cannot start a conversation for a declined request', format($$select public.start_request_conversation('%s')$$, (select rid from rq2)), 'request_not_pending');

-- expired plan + pending request
select t.login('c0000000-0000-0000-0000-00000000000c');
select public.request_to_join((select walk from ids));
select t.root();
create temp table rq3 as select id as rid from public.join_requests where requester_id = 'c0000000-0000-0000-0000-00000000000c' and status = 'pending';
grant all on rq3 to public;
select t.login('a0000000-0000-0000-0000-00000000000a');
create temp table conv3 as select public.start_request_conversation((select rid from rq3)) as cid;
grant all on conv3 to public;
select t.root();
select t.check('different applicant gets a different conversation', (select cid from conv3) <> (select cid from conv));

-- ===== 7. accepting after chatting keeps the same conversation, identity still hidden
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('accept works after messaging', public.respond_to_join_request((select rid from rq3), true) = 'accepted');
select t.root();
select t.check('accepting reused the pre-approval conversation', (select count(*) from public.conversations where activity_id = (select walk from ids) and id = (select cid from conv3)) = 1
                                                                 and (select count(*) from public.conversations where activity_id = (select walk from ids)) = 2);
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('accepted guest can chat', public.send_message((select cid from conv3), 'Thanks for having me') is not null);
select t.check('accepted guest still cannot see the organizer id', position('a0000000-0000-0000-0000-00000000000a' in (public.list_my_conversations()::text || public.list_my_messages()::text)) = 0);

-- live walk session masking
select t.login('c0000000-0000-0000-0000-00000000000c');
create temp table sess as select public.open_walk_session((select walk from ids)) as j;
grant all on sess to public;
select t.check('walk session never names the anonymous organizer', position('a0000000-0000-0000-0000-00000000000a' in (select j::text from sess)) = 0
                                                                   and position('Alice' in (select j::text from sess)) = 0);
select t.check('walk session shows the anonymous placeholder', (select j::text from sess) like '%Anonymous Walker%');

-- ===== 8. blocking an anonymous organizer ====================================
select t.login('d0000000-0000-0000-0000-00000000000d');
select public.request_to_join((select walk from ids));
select public.block_walk_host((select walk from ids));
select t.check('blocker cannot see the block row (it would reveal the id)', t.scalar($$select count(*) from public.user_blocks$$) = 0);
select t.root();
select t.check('block is recorded and concealed', (select count(*) from public.user_blocks where blocker_id = 'd0000000-0000-0000-0000-00000000000d' and concealed) = 1);
select t.check('block cancelled their pending request', (select status from public.join_requests where requester_id = 'd0000000-0000-0000-0000-00000000000d') = 'cancelled');
select t.check('block row does not store the organizer name', (select blocked_display_name from public.user_blocks where blocker_id = 'd0000000-0000-0000-0000-00000000000d') = 'Anonymous Walker');

-- ===== 9. reveal =============================================================
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.expect_error('only the organizer can reveal', format($$select public.reveal_walk_host('%s')$$, (select walk from ids)), 'not_found');
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.reveal_walk_host((select walk from ids));
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('after the organizer reveals, the card shows who they are',
  (select host_name from public.discover_activities(-74.05, 40.70, -73.90, 40.80) where title = 'Overthinking Our Careers') = 'Alice');

select t.root();
select * from t.log where not ok order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
