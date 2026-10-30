\set ON_ERROR_STOP on
select t.root();

-- Users: alice (host), bob (guest), carol (guest), dave (will be blocked), erin (profile left incomplete)
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-00000000000a', 'alice@test', '{"full_name":"Alice Anderson"}'),
  ('b0000000-0000-0000-0000-00000000000b', 'bob@test',   '{"full_name":"Bob Brown"}'),
  ('c0000000-0000-0000-0000-00000000000c', 'carol@test', '{}'),
  ('d0000000-0000-0000-0000-00000000000d', 'dave@test',  '{}'),
  ('e0000000-0000-0000-0000-00000000000e', 'erin@test',  '{}');

select t.check('trigger created a profile for every user', t.scalar('select count(*) from public.profiles') = 5);
select t.check('Manhattan polygon is valid',
  (select extensions.ST_IsValid(boundary) from private.geo_regions where name = 'manhattan'));

-- Complete profiles through the RPC (alice..dave). erin stays incomplete.
do $$
declare u record;
begin
  for u in select * from (values
      ('a0000000-0000-0000-0000-00000000000a'::uuid, 'Alice', 'everyone'),
      ('b0000000-0000-0000-0000-00000000000b'::uuid, 'Bob', 'activity_members'),
      ('c0000000-0000-0000-0000-00000000000c'::uuid, 'Carol', 'everyone'),
      ('d0000000-0000-0000-0000-00000000000d'::uuid, 'Dave', 'everyone')) v(id, n, vis) loop
    perform t.login(u.id);
    perform public.complete_profile(u.n, 'Hi, I am ' || u.n, array['coffee','walking'], array['walking_buddies'], true);
    update public.profiles set visibility = u.vis where id = u.id;
  end loop;
  perform t.root();
end $$;

-- ===== profiles ===========================================================
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('anyone signed in sees "everyone" profiles', t.scalar($$select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-00000000000a'$$) = 1);
select t.check('restricted profile hidden from strangers', t.scalar($$select count(*) from public.profiles where id = 'b0000000-0000-0000-0000-00000000000b'$$) = 0);
select t.expect_error('full_name column is not readable by others', $$select full_name from public.profiles where id = 'a0000000-0000-0000-0000-00000000000a'$$, 'permission denied');
select t.expect_error('age_confirmed_at is not readable', $$select age_confirmed_at from public.profiles$$, 'permission denied');
select t.expect_error('cannot insert profiles directly', $$insert into public.profiles (id) values (gen_random_uuid())$$, 'permission denied');
select t.expect_error('cannot set own age_confirmed_at', $$update public.profiles set age_confirmed_at = null where id = auth.uid()$$, 'permission denied');
update public.profiles set bio = 'hacked' where id = 'a0000000-0000-0000-0000-00000000000a';
select t.root();
select t.check('cannot edit another user''s profile', (select bio from public.profiles where id = 'a0000000-0000-0000-0000-00000000000a') <> 'hacked');
select t.login('a0000000-0000-0000-0000-00000000000a');
update public.profiles set bio = 'my new bio' where id = auth.uid();
select t.check('owner can edit own profile', (select bio from public.profiles where id = auth.uid()) = 'my new bio');
select t.check('owner reads own full_name via get_my_profile()', (select full_name from public.get_my_profile()) = 'Alice Anderson');
select t.anon();
select t.expect_error('anon blocked from profiles', $$select * from public.profiles$$, 'permission denied');
select t.expect_error('anon blocked from RPC', $$select * from public.discover_activities(-74.1,40.6,-73.9,40.9)$$, 'permission denied');

-- ===== creating activities ===============================================
select t.login('e0000000-0000-0000-0000-00000000000e');
select t.expect_error('incomplete profile cannot create', $$select public.create_cowork('x','',now()+interval '1 hour',now()+interval '2 hours',2,'public','social','Cafe','',-73.99,40.74)$$, 'profile_incomplete');
select t.expect_error('incomplete profile cannot request', $$select public.request_to_join(gen_random_uuid())$$, 'profile_incomplete');

select t.login('a0000000-0000-0000-0000-00000000000a');
select t.expect_error('walk outside Manhattan rejected', $$select public.create_walk('Brooklyn walk','',now()+interval '1 hour',now()+interval '2 hours',2,'public','casual','A','B',-73.969,40.660,-73.960,40.670)$$, 'outside_manhattan');
select t.expect_error('cowork outside Manhattan rejected', $$select public.create_cowork('x','',now()+interval '1 hour',now()+interval '2 hours',2,'public','social','Cafe','',-73.9442,40.6782)$$, 'outside_manhattan');
select t.expect_error('walk in the past rejected', $$select public.create_walk('Past','',now()-interval '3 hours',now()-interval '2 hours',2,'public','casual','72nd St','55th St',-73.9681,40.7726,-73.9754,40.7619)$$, 'start_in_past');
select t.expect_error('end before start rejected', $$select public.create_cowork('x','',now()+interval '2 hours',now()+interval '1 hour',2,'public','social','Cafe','',-73.99,40.74)$$, 'invalid_times');
select t.expect_error('same start/end rejected', $$select public.create_walk('Same','',now()+interval '1 hour',now()+interval '2 hours',2,'public','casual','A','A',-73.9681,40.7726,-73.9681,40.7726)$$, 'same_location');
select t.expect_error('capacity 0 rejected', $$select public.create_cowork('x','',now()+interval '1 hour',now()+interval '2 hours',0,'public','social','Cafe','',-73.99,40.74)$$, 'invalid_capacity');
select t.expect_error('capacity 6 rejected', $$select public.create_cowork('x','',now()+interval '1 hour',now()+interval '2 hours',6,'public','social','Cafe','',-73.99,40.74)$$, 'invalid_capacity');
select t.expect_error('direct insert into activities denied', $$insert into public.activities (creator_id,type,title,start_time,end_time,max_participants) values (auth.uid(),'walk','x',now(),now()+interval '1 hour',2)$$, 'permission denied');
select t.expect_error('direct insert into walk_routes denied', $$insert into public.walk_routes (activity_id) values (gen_random_uuid())$$, 'permission denied');

-- Atomicity: a failing route must not leave an orphan activity behind.
select t.expect_error('invalid route vertices rejected', $$select public.create_walk('Bad route','',now()+interval '1 hour',now()+interval '2 hours',2,'public','casual','72nd St','55th St',-73.9681,40.7726,-73.9754,40.7619,'[[-73.9681,40.7726],[-73.5,40.2]]'::jsonb)$$, 'invalid_route');
select t.root();
select t.check('failed walk left no orphan activity', t.scalar($$select count(*) from public.activities where title = 'Bad route'$$) = 0);
select t.login('a0000000-0000-0000-0000-00000000000a');

select t.check('riverside route vertex just outside the rough outline is accepted',
  private.is_near_manhattan(-74.0215, 40.7150) and not private.is_near_manhattan(-74.0500, 40.7150));
create temp table ids (name text primary key, id uuid);
grant all on ids to public;
insert into ids select 'walk', public.create_walk('Evening walk to Midtown','Getting my steps in',now()+interval '3 hours',now()+interval '4 hours',1,'public','casual','72nd St','55th St',-73.9681,40.7726,-73.9754,40.7619,'[[-73.9681,40.7726],[-73.9720,40.7680],[-73.9754,40.7619]]'::jsonb,'South-west corner of 72nd & Broadway');
insert into ids select 'cowork', public.create_cowork('Working from SoHo','Building a startup',now()+interval '5 hours',now()+interval '9 hours',2,'public','deep_work','Lantern Coffee','142 Prince St',-74.0003,40.7233,'place-123','Big table by the window');
insert into ids select 'private', public.create_cowork('Private session','secret',now()+interval '5 hours',now()+interval '6 hours',2,'private','social','Secret Cafe','1 Secret St',-73.9890,40.7411);
insert into ids select 'ues', public.create_walk('East side stroll','',now()+interval '1 day',now()+interval '1 day 1 hour',3,'public','moderate','79th St','96th St',-73.9560,40.7790,-73.9490,40.7860);

select t.check('walk public location is snapped (not exact)',
  (select extensions.ST_X(public_start_point::extensions.geometry) <> -73.9681 from public.walk_routes where activity_id = (select id from ids where name='walk')));
select t.root();
select t.check('distance stored by server', (select distance_meters between 50 and 20000 from public.walk_routes where activity_id=(select id from ids where name='walk')));
select t.check('public area derived by server', (select public_area from public.cowork_locations where activity_id=(select id from ids where name='cowork')) = 'SoHo');

-- ===== location privacy ===================================================
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.expect_error('precise walk coordinates not selectable', $$select start_coordinates from public.walk_routes$$, 'permission denied');
select t.expect_error('route_geometry not selectable', $$select route_geometry from public.walk_routes$$, 'permission denied');
select t.expect_error('walk meeting_details not selectable', $$select meeting_details from public.walk_routes$$, 'permission denied');
select t.expect_error('cafe name not selectable', $$select cafe_name from public.cowork_locations$$, 'permission denied');
select t.expect_error('cafe lat/lng not selectable', $$select latitude, longitude from public.cowork_locations$$, 'permission denied');
select t.expect_error('select * on cowork_locations denied', $$select * from public.cowork_locations$$, 'permission denied');
select t.check('public columns are readable', t.scalar('select count(*) from (select public_area, public_point from public.cowork_locations) s') >= 1);
select t.check('private activity invisible to strangers', t.scalar($$select count(*) from public.activities where title = 'Private session'$$) = 0);
select t.check('stranger gets no private details', t.scalar($$select count(*) from public.get_private_activity_details(array(select id from ids))$$) = 0);

-- discovery
select t.check('discover: bbox over Manhattan returns public plans only',
  t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90)$$) = 3);
select t.check('discover: private plan never returned',
  t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90) where title = 'Private session'$$) = 0);
select t.check('discover: type filter', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90,'walk')$$) = 2);
select t.check('discover: small bbox around SoHo only', t.scalar($$select count(*) from public.discover_activities(-74.01,40.72,-73.99,40.73)$$) = 1);
select t.check('discover: time window excludes later plans', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90,null,now(),now()+interval '10 hours')$$) = 2);
select t.check('discover: pagination limit', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90,null,null,null,2,0)$$) = 2);
select t.check('discover: pagination offset', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90,null,null,null,2,2)$$) = 1);
select t.check('discover: results ordered by start time', (select array_agg(title order by ord) = array['Evening walk to Midtown','Working from SoHo','East side stroll'] from (select title, row_number() over () ord from public.discover_activities(-74.05,40.68,-73.90,40.90)) s));
select t.check('discover: host display name present', (select bool_and(host_name in ('Alice')) from public.discover_activities(-74.05,40.68,-73.90,40.90)));
select t.expect_error('discover: huge bbox rejected', $$select * from public.discover_activities(-80,30,-70,45)$$, 'invalid_bounds');
select t.check('nearby: 2 km around SoHo', t.scalar($$select count(*) from public.nearby_activities(-74.0003,40.7233,2000)$$) = 1);
select t.check('nearby: 20 km radius reaches all public', t.scalar($$select count(*) from public.nearby_activities(-73.98,40.75,20000)$$) = 3);
select t.expect_error('nearby: radius capped', $$select * from public.nearby_activities(-73.98,40.75,50000)$$, 'invalid_bounds');
select t.check('card for non-members carries no precise flag', (select bool_and(not viewer_is_creator and not viewer_is_participant) from public.discover_activities(-74.05,40.68,-73.90,40.90)));

-- ===== join requests ======================================================
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.expect_error('host cannot request own activity', format($$select public.request_to_join('%s')$$, (select id from ids where name='walk')), 'own_activity');

select t.login('b0000000-0000-0000-0000-00000000000b');
insert into ids select 'req_bob_walk', public.request_to_join((select id from ids where name='walk'));
select t.expect_error('duplicate active request rejected', format($$select public.request_to_join('%s')$$, (select id from ids where name='walk')), 'already_requested');
select t.expect_error('private activity cannot be requested', format($$select public.request_to_join('%s')$$, (select id from ids where name='private')), 'not_found');
select t.check('requester sees own request', t.scalar('select count(*) from public.join_requests') = 1);
select t.check('requester sees the activity they requested', t.scalar(format($$select count(*) from public.activities where id = '%s'$$, (select id from ids where name='walk'))) = 1);
select t.check('host profile visible to requester', t.scalar($$select count(*) from public.profiles where id='a0000000-0000-0000-0000-00000000000a'$$) = 1);
select t.expect_error('requester cannot self-accept', format($$select public.respond_to_join_request('%s', true)$$, (select id from ids where name='req_bob_walk')), 'not_found');
select t.expect_error('requester cannot update request directly', $$update public.join_requests set status='accepted'$$, 'permission denied');
select t.check('no private details while pending', t.scalar(format($$select count(*) from public.get_private_activity_details(array['%s'::uuid])$$, (select id from ids where name='walk'))) = 0);

-- carol cannot see bob's request
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('other users cannot see requests', t.scalar('select count(*) from public.join_requests') = 0);
insert into ids select 'req_carol_walk', public.request_to_join((select id from ids where name='walk'));

-- host sees both, and can read restricted requester profile (bob) because of the request
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('host sees incoming requests', t.scalar('select count(*) from public.join_requests') = 2);
select t.check('host can read requester with restricted profile', t.scalar($$select count(*) from public.profiles where id='b0000000-0000-0000-0000-00000000000b'$$) = 1);

-- capacity 1: accept bob → carol's accept must fail
select t.check('accept returns accepted', public.respond_to_join_request((select id from ids where name='req_bob_walk'), true) = 'accepted');
select t.expect_error('capacity enforced on second accept', format($$select public.respond_to_join_request('%s', true)$$, (select id from ids where name='req_carol_walk')), 'activity_full');
select t.expect_error('cannot respond twice', format($$select public.respond_to_join_request('%s', true)$$, (select id from ids where name='req_bob_walk')), 'request_not_pending');
select t.check('host can decline carol', public.respond_to_join_request((select id from ids where name='req_carol_walk'), false) = 'declined');
select t.check('conversation created on accept', t.scalar('select count(*) from public.conversations') = 1);
select t.check('conversation has host+guest', t.scalar('select count(*) from public.conversation_participants') = 2);

select t.login('c0000000-0000-0000-0000-00000000000c');
select t.expect_error('declined user cannot re-request', format($$select public.request_to_join('%s')$$, (select id from ids where name='walk')), 'request_declined');
select t.check('declined user sees status declined', (select status from public.join_requests limit 1) = 'declined');
select t.check('non-member cannot see conversations', t.scalar('select count(*) from public.conversations') = 0);
select t.check('card shows participant_count = 1', (select participant_count from public.discover_activities(-74.05,40.68,-73.90,40.90) where title='Evening walk to Midtown') = 1);
select t.expect_error('declined user still cannot request (even though full)', format($$select public.request_to_join('%s')$$, (select id from ids where name='walk')), 'request_declined');

-- precise details after acceptance
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.check('accepted guest receives precise details', (select meeting_details from public.get_private_activity_details(array[(select id from ids where name='walk')])) = 'South-west corner of 72nd & Broadway');
select t.check('accepted guest receives exact route', (select jsonb_array_length(route_coordinates) from public.get_private_activity_details(array[(select id from ids where name='walk')])) = 3);
select t.check('card flags viewer as participant', (select viewer_is_participant from public.list_my_activities() where title='Evening walk to Midtown'));

-- ===== messaging ===========================================================
select t.check('guest sees conversation', t.scalar('select count(*) from public.conversations') = 1);
insert into ids select 'conv', (select id from public.conversations limit 1);
select t.expect_error('cannot spoof sender', format($$insert into public.messages (conversation_id, sender_id, content) values ('%s','a0000000-0000-0000-0000-00000000000a','hi')$$, (select id from ids where name='conv')), 'row-level security');
insert into public.messages (conversation_id, content) values ((select id from ids where name='conv'), 'Hello host!');
select t.check('guest can send', t.scalar('select count(*) from public.messages') = 1);
select t.expect_error('empty message rejected', format($$insert into public.messages (conversation_id, content) values ('%s','   ')$$, (select id from ids where name='conv')), 'violates check constraint');
select t.expect_error('messages cannot be edited', $$update public.messages set content='x'$$, 'permission denied');

select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('host reads guest message', (select content from public.messages limit 1) = 'Hello host!');
insert into public.messages (conversation_id, content) values ((select id from ids where name='conv'), 'Welcome!');
select t.check('host can reply', t.scalar('select count(*) from public.messages') = 2);

select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('outsider cannot read messages', t.scalar('select count(*) from public.messages') = 0);
select t.expect_error('outsider cannot send', format($$insert into public.messages (conversation_id, content) values ('%s','intrude')$$, (select id from ids where name='conv')), 'row-level security');
select t.check('outsider cannot see participants', t.scalar('select count(*) from public.conversation_participants') = 0);

-- guest leaves → chat closes, history stays readable
select t.login('b0000000-0000-0000-0000-00000000000b');
select public.leave_activity((select id from ids where name='walk'));
select t.expect_error('cannot message after leaving', format($$insert into public.messages (conversation_id, content) values ('%s','still here?')$$, (select id from ids where name='conv')), 'row-level security');
select t.check('history remains readable', t.scalar('select count(*) from public.messages') = 2);
select t.check('leaving frees the spot', (select participant_count from public.list_my_activities() where title='Evening walk to Midtown') = 0);
select t.check('no private details after leaving', t.scalar(format($$select count(*) from public.get_private_activity_details(array['%s'::uuid])$$, (select id from ids where name='walk'))) = 0);

-- ===== cancel pending / cancel_join_request ==================================
select t.login('b0000000-0000-0000-0000-00000000000b');
insert into ids select 'req_bob_cowork', public.request_to_join((select id from ids where name='cowork'));
select public.cancel_join_request((select id from ids where name='req_bob_cowork'));
select t.check('requester can cancel pending', (select status from public.join_requests where id=(select id from ids where name='req_bob_cowork')) = 'cancelled');
select t.expect_error('cannot cancel twice', format($$select public.cancel_join_request('%s')$$, (select id from ids where name='req_bob_cowork')), 'not_found');
insert into ids select 'req_bob_cowork2', public.request_to_join((select id from ids where name='cowork'));   -- re-request after cancel is allowed

-- ===== blocking ==============================================================
select t.login('d0000000-0000-0000-0000-00000000000d');
insert into ids select 'req_dave_cowork', public.request_to_join((select id from ids where name='cowork'));
select t.login('a0000000-0000-0000-0000-00000000000a');
select t.check('host sees dave pending', t.scalar(format($$select count(*) from public.join_requests where id='%s'$$, (select id from ids where name='req_dave_cowork'))) = 1);
select public.respond_to_join_request((select id from ids where name='req_dave_cowork'), true);
select public.block_user('d0000000-0000-0000-0000-00000000000d');
select t.check('blocker no longer sees blocked user''s profile', t.scalar($$select count(*) from public.profiles where id='d0000000-0000-0000-0000-00000000000d'$$) = 0);
select t.check('blocker still lists the block (with name snapshot)', (select blocked_display_name from public.user_blocks) = 'Dave');
select t.check('block cancelled their accepted request', t.scalar(format($$select count(*) from public.join_requests where id='%s'$$, (select id from ids where name='req_dave_cowork'))) = 0);
select t.root();
select t.check('block set request to cancelled', (select status from public.join_requests where id=(select id from ids where name='req_dave_cowork')) = 'cancelled');
select t.login('d0000000-0000-0000-0000-00000000000d');
select t.check('blocked user cannot discover blocker''s plans', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90) where creator_id='a0000000-0000-0000-0000-00000000000a'$$) = 0);
select t.expect_error('blocked user cannot request blocker''s plan', format($$select public.request_to_join('%s')$$, (select id from ids where name='ues')), 'not_found');
select t.check('blocked user cannot read blocker''s profile', t.scalar($$select count(*) from public.profiles where id='a0000000-0000-0000-0000-00000000000a'$$) = 0);
select t.check('blocked user cannot see block row', t.scalar('select count(*) from public.user_blocks') = 0);
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.unblock_user('d0000000-0000-0000-0000-00000000000d');
select t.check('unblock restores visibility', t.scalar($$select count(*) from public.profiles where id='d0000000-0000-0000-0000-00000000000d'$$) = 1);
-- users can only manage their own blocks
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.expect_error('cannot insert a block as someone else', $$insert into public.user_blocks (blocker_id, blocked_id) values ('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b')$$, 'row-level security');

-- block hides conversation and stops messaging both ways
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.respond_to_join_request((select id from ids where name='req_bob_cowork2'), true);
-- host now has: walk↔bob, cowork↔dave (re-visible after unblock), cowork↔bob
select t.check('host sees all three conversations', t.scalar('select count(*) from public.conversations') = 3);
select public.block_user('b0000000-0000-0000-0000-00000000000b');
select t.check('blocking hides every conversation with that user', t.scalar('select count(*) from public.conversations') = 1);
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.check('blocked guest cannot see the conversation either', t.scalar('select count(*) from public.conversations') = 0);
select t.check('blocked guest cannot read messages', t.scalar('select count(*) from public.messages') = 0);
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.unblock_user('b0000000-0000-0000-0000-00000000000b');

-- ===== editing and cancelling =================================================
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.expect_error('non-creator cannot edit', format($$select public.update_activity('%s', 'Hijacked')$$, (select id from ids where name='cowork')), 'not_found');
select t.expect_error('non-creator cannot cancel', format($$select public.cancel_activity('%s')$$, (select id from ids where name='cowork')), 'not_found');
select t.login('a0000000-0000-0000-0000-00000000000a');
select public.update_activity((select id from ids where name='ues'), 'East side stroll (updated)', 'New note', null, null, 4, 'By the river entrance');
select t.check('creator can edit', (select title from public.activities where id=(select id from ids where name='ues')) = 'East side stroll (updated)');
select t.expect_error('cannot shrink below accepted guests', format($$select public.update_activity('%s', null, null, null, null, 0)$$, (select id from ids where name='cowork')), 'invalid_capacity');
select t.expect_error('edit validates times', format($$select public.update_activity('%s', null, null, now()-interval '1 day', null)$$, (select id from ids where name='ues')), 'start_in_past');
-- cowork has bob accepted (cowork2) → capacity 1 < accepted? accepted=1, so capacity 1 is OK, but 0 isn't
select public.cancel_activity((select id from ids where name='cowork'));
select t.check('cancel sets status', (select status from public.activities where id=(select id from ids where name='cowork')) = 'cancelled');
select t.check('cancelled plan leaves discovery', t.scalar($$select count(*) from public.discover_activities(-74.05,40.68,-73.90,40.90) where title='Working from SoHo'$$) = 0);
select t.login('b0000000-0000-0000-0000-00000000000b');
select t.expect_error('chat closed after cancellation', format($$insert into public.messages (conversation_id, content) values ((select c.id from public.conversations c where c.activity_id='%s'),'hello?')$$, (select id from ids where name='cowork')), 'row-level security');
select t.check('guest still sees cancelled plan in their list', (select status from public.list_my_activities() where title='Working from SoHo') = 'cancelled');

-- ===== storage policies =======================================================
select t.login('a0000000-0000-0000-0000-00000000000a');
insert into storage.objects (bucket_id, name, owner) values ('avatars', 'a0000000-0000-0000-0000-00000000000a/avatar-1.jpg', auth.uid());
select t.check('user can upload to own folder', true);
select t.expect_error('cannot upload to another user''s folder', $$insert into storage.objects (bucket_id, name) values ('avatars','b0000000-0000-0000-0000-00000000000b/avatar-1.jpg')$$, 'row-level security');
select t.expect_error('rejects non-image names', $$insert into storage.objects (bucket_id, name) values ('avatars','a0000000-0000-0000-0000-00000000000a/evil.exe')$$, 'row-level security');
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('visible profile avatar is readable', t.scalar($$select count(*) from storage.objects where bucket_id='avatars'$$) = 1);
select t.login('b0000000-0000-0000-0000-00000000000b');
insert into storage.objects (bucket_id, name) values ('avatars', 'b0000000-0000-0000-0000-00000000000b/avatar-2.png');
select t.login('c0000000-0000-0000-0000-00000000000c');
select t.check('restricted profile avatar is not readable by strangers', t.scalar($$select count(*) from storage.objects where bucket_id='avatars' and name like 'b0000%'$$) = 0);
delete from storage.objects where name like 'a0000%';
select t.root();
select t.check('cannot delete another user''s avatar', t.scalar($$select count(*) from storage.objects where name like 'a0000%'$$) = 1);

-- ===== reports ============================================================
select t.login('c0000000-0000-0000-0000-00000000000c');
select public.report_content('user', 'a0000000-0000-0000-0000-00000000000a', 'spam', 'looks fake');
select public.report_content('activity', (select id from ids where name='walk'), 'unsafe');
select t.expect_error('reports table is not readable', $$select * from public.reports$$, 'permission denied');
select t.expect_error('reports cannot be inserted directly', $$insert into public.reports (reporter_id,target_type,target_id,reason) values (auth.uid(),'user',gen_random_uuid(),'spam')$$, 'permission denied');
select t.expect_error('invalid reason rejected', $$select public.report_content('user', gen_random_uuid(), 'because')$$, 'not_allowed');
select t.root();
select t.check('reports were stored', t.scalar('select count(*) from public.reports') = 2);
select t.anon();
select t.expect_error('anon cannot report', $$select public.report_content('user', gen_random_uuid(), 'spam')$$, 'permission denied');
select t.root();

-- ===== account deletion cascades ==============================================
select t.login('d0000000-0000-0000-0000-00000000000d');
select public.delete_my_account();
select t.root();
select t.check('delete_my_account removes auth user + profile', t.scalar($$select count(*) from auth.users where id='d0000000-0000-0000-0000-00000000000d'$$) = 0 and t.scalar($$select count(*) from public.profiles where id='d0000000-0000-0000-0000-00000000000d'$$) = 0);
select t.check('deleted user''s requests cascade', t.scalar($$select count(*) from public.join_requests where requester_id='d0000000-0000-0000-0000-00000000000d'$$) = 0);

-- ===== misc invariants ========================================================
select t.check('RLS enabled on every user-facing table', (select bool_and(relrowsecurity) from pg_class where oid in (
  'public.profiles'::regclass,'public.activities'::regclass,'public.walk_routes'::regclass,'public.cowork_locations'::regclass,
  'public.join_requests'::regclass,'public.conversations'::regclass,'public.conversation_participants'::regclass,
  'public.messages'::regclass,'public.user_blocks'::regclass)));
select t.check('GiST indexes exist on geography columns', (select count(*) from pg_indexes where schemaname='public' and indexdef ilike '%using gist%') >= 6);
select t.check('realtime publication has the 4 tables', (select count(*) from pg_publication_tables where pubname='supabase_realtime') = 4);
select t.check('anon has no table privileges', not exists (select 1 from information_schema.role_table_grants where grantee='anon' and table_schema='public'));
select t.check('only one active request index', exists (select 1 from pg_indexes where indexname='join_requests_one_active_idx'));

-- ===== report =================================================================
\echo
select case when ok then 'PASS' else 'FAIL' end as result, name, case when ok then '' else detail end as detail from t.log order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t.log;
