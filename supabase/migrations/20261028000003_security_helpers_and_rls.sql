-- Along · migration 3 — security helpers, Row Level Security, column privileges
--
-- Model:
--   * Every user-facing table has RLS enabled; there are NO write policies for activities, routes, locations,
--     join_requests or conversations → clients cannot write them directly. All writes go through the
--     SECURITY DEFINER RPCs in migration 4, which validate, enforce capacity and keep writes atomic.
--   * Precise location columns have no SELECT grant for clients. They are only returned by
--     public.get_private_activity_details() to the creator and accepted guests.
--   * Helper functions live in the `private` schema (not exposed by the Data API) and always compare against
--     auth.uid(), so they can't be used to probe other people's relationships.

-- ---------------------------------------------------------------------------
-- helpers (SECURITY DEFINER so they can read tables without recursing into RLS)
-- ---------------------------------------------------------------------------

-- True when the current user and `p_other` have blocked each other in either direction.
create or replace function private.blocked_with(p_other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
       or (b.blocker_id = p_other and b.blocked_id = auth.uid())
  )
$$;

create or replace function private.activity_creator(p_activity uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select creator_id from public.activities where id = p_activity
$$;

create or replace function private.is_creator(p_activity uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.activities where id = p_activity and creator_id = auth.uid())
$$;

create or replace function private.is_accepted_guest(p_activity uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.join_requests
                 where activity_id = p_activity and requester_id = auth.uid() and status = 'accepted')
$$;

-- Can the current user see this activity at all? (creator, someone who asked to join, or a public live plan)
create or replace function private.can_see_activity(p_activity uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.activities a
    where a.id = p_activity
      and not private.blocked_with(a.creator_id)
      and (
        a.creator_id = auth.uid()
        or exists (select 1 from public.join_requests r where r.activity_id = a.id and r.requester_id = auth.uid())
        or (a.visibility = 'public' and a.status = 'active' and a.end_time > now())
      )
  )
$$;

-- Do the current user and `p_other` have a pending/accepted request between them? (drives profile visibility)
create or replace function private.shares_context(p_other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.join_requests r
    join public.activities a on a.id = r.activity_id
    where r.status in ('pending', 'accepted')
      and ((a.creator_id = auth.uid() and r.requester_id = p_other)
        or (a.creator_id = p_other and r.requester_id = auth.uid()))
  )
$$;

create or replace function private.in_conversation(p_conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_participants
                 where conversation_id = p_conversation and user_id = auth.uid())
$$;

-- True when any other participant has blocked, or is blocked by, the current user.
create or replace function private.conversation_blocked(p_conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = p_conversation and cp.user_id <> auth.uid() and private.blocked_with(cp.user_id)
  )
$$;

-- A conversation accepts new messages only while: the viewer is in it, nobody is blocked, the plan isn't
-- cancelled, and every guest in it still holds an accepted request.
create or replace function private.can_message(p_conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.conversations c
    join public.activities a on a.id = c.activity_id
    where c.id = p_conversation
      and a.status <> 'cancelled'
      and private.in_conversation(c.id)
      and not private.conversation_blocked(c.id)
      and exists (select 1 from public.conversation_participants g
                  where g.conversation_id = c.id and g.user_id <> a.creator_id)
      and not exists (
        select 1 from public.conversation_participants g
        where g.conversation_id = c.id and g.user_id <> a.creator_id
          and not exists (select 1 from public.join_requests r
                          where r.activity_id = a.id and r.requester_id = g.user_id and r.status = 'accepted'))
  )
$$;

grant execute on function
  private.blocked_with(uuid), private.activity_creator(uuid), private.is_creator(uuid),
  private.is_accepted_guest(uuid), private.can_see_activity(uuid), private.shares_context(uuid),
  private.in_conversation(uuid), private.conversation_blocked(uuid), private.can_message(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- Baseline: nothing is reachable until explicitly granted. `anon` gets nothing at all.
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.activities, public.walk_routes, public.cowork_locations,
              public.join_requests, public.conversations, public.conversation_participants,
              public.messages, public.user_blocks
  from anon, authenticated;

alter table public.profiles                  enable row level security;
alter table public.activities                enable row level security;
alter table public.walk_routes               enable row level security;
alter table public.cowork_locations          enable row level security;
alter table public.join_requests             enable row level security;
alter table public.conversations             enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages                  enable row level security;
alter table public.user_blocks               enable row level security;

-- ---------------------------------------------------------------------------
-- profiles — own row always; others according to their visibility setting; blocked users never.
-- `full_name` and `age_confirmed_at` have no SELECT grant (returned to the owner only via get_my_profile()).
-- ---------------------------------------------------------------------------
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or (not private.blocked_with(id) and (visibility = 'everyone' or private.shares_context(id)))
  );

create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

grant select (id, username, display_name, bio, avatar_url, interests, looking_for, visibility, created_at, updated_at)
  on public.profiles to authenticated;
grant update (username, full_name, display_name, bio, avatar_url, interests, looking_for, visibility)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- activities — read only. Private plans are visible to their creator only.
-- ---------------------------------------------------------------------------
create policy activities_select on public.activities for select to authenticated
  using (private.can_see_activity(id));

grant select on public.activities to authenticated;

-- ---------------------------------------------------------------------------
-- walk_routes / cowork_locations — rows follow activity visibility; only PUBLIC columns are granted.
-- ---------------------------------------------------------------------------
create policy walk_routes_select on public.walk_routes for select to authenticated
  using (private.can_see_activity(activity_id));
grant select (id, activity_id, pace, public_start_location, public_end_location, public_area,
              public_start_point, public_end_point, public_route_geometry, distance_meters)
  on public.walk_routes to authenticated;

create policy cowork_locations_select on public.cowork_locations for select to authenticated
  using (private.can_see_activity(activity_id));
grant select (id, activity_id, work_style, public_area, public_point)
  on public.cowork_locations to authenticated;

-- ---------------------------------------------------------------------------
-- join_requests — requester sees their own; the activity creator sees requests for their activity.
-- ---------------------------------------------------------------------------
create policy join_requests_select on public.join_requests for select to authenticated
  using (
    (requester_id = auth.uid() and not private.blocked_with(private.activity_creator(activity_id)))
    or (private.is_creator(activity_id) and not private.blocked_with(requester_id))
  );
grant select on public.join_requests to authenticated;

-- ---------------------------------------------------------------------------
-- conversations, participants, messages
-- ---------------------------------------------------------------------------
create policy conversations_select on public.conversations for select to authenticated
  using (private.in_conversation(id) and not private.conversation_blocked(id));
grant select on public.conversations to authenticated;

create policy conversation_participants_select on public.conversation_participants for select to authenticated
  using (private.in_conversation(conversation_id) and not private.conversation_blocked(conversation_id));
grant select on public.conversation_participants to authenticated;

create policy messages_select on public.messages for select to authenticated
  using (private.in_conversation(conversation_id) and not private.conversation_blocked(conversation_id));

-- Users may only send as themselves, and only into a conversation that is currently open.
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and private.can_message(conversation_id));

grant select on public.messages to authenticated;
grant insert (conversation_id, sender_id, content) on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- user_blocks — manage only your own block list. (The blocked person can't see that they were blocked.)
-- ---------------------------------------------------------------------------
create policy user_blocks_select_own on public.user_blocks for select to authenticated
  using (blocker_id = auth.uid());
create policy user_blocks_insert_own on public.user_blocks for insert to authenticated
  with check (blocker_id = auth.uid());
create policy user_blocks_delete_own on public.user_blocks for delete to authenticated
  using (blocker_id = auth.uid());

grant select, delete on public.user_blocks to authenticated;
grant insert (blocker_id, blocked_id) on public.user_blocks to authenticated;
