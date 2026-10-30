-- Along · migration 2 — core tables, constraints, indexes, triggers

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  username         text unique check (username ~ '^[a-z0-9_]{3,24}$'),
  full_name        text check (char_length(full_name) <= 100),               -- private: never returned to other users
  display_name     text check (char_length(display_name) between 1 and 24),
  bio              text not null default '' check (char_length(bio) <= 160),
  avatar_url       text check (char_length(avatar_url) <= 200),              -- Storage object path inside the `avatars` bucket
  interests        text[] not null default '{}'
                     check (cardinality(interests) <= 12
                            and interests <@ array['tech','coffee','startups','fitness','art','design','books','walking']),
  looking_for      text[] not null default '{}'
                     check (looking_for <@ array['walking_buddies','coworking_company']),
  visibility       text not null default 'everyone' check (visibility in ('everyone', 'activity_members')),
  age_confirmed_at timestamptz,                                              -- server-set 18+ self-declaration timestamp
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Create a profile row automatically for every new auth user. Never overwrites an existing profile.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 100), ''))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- activities (walks and cowork sessions)
-- ---------------------------------------------------------------------------
create table public.activities (
  id               uuid primary key default gen_random_uuid(),
  creator_id       uuid not null references public.profiles (id) on delete cascade,
  type             text not null check (type in ('walk', 'cowork')),
  title            text not null check (char_length(btrim(title)) between 1 and 80),
  description      text not null default '' check (char_length(description) <= 280),
  start_time       timestamptz not null,
  end_time         timestamptz not null,
  max_participants smallint not null check (max_participants between 1 and 5),
  visibility       text not null default 'public' check (visibility in ('public', 'private')),
  status           text not null default 'active' check (status in ('active', 'cancelled', 'completed')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint activities_time_order check (end_time > start_time)
);
create trigger activities_set_updated_at before update on public.activities
  for each row execute function public.set_updated_at();
create index activities_discovery_idx on public.activities (start_time, end_time)
  where status = 'active' and visibility = 'public';
create index activities_creator_idx on public.activities (creator_id, start_time desc);
create index activities_type_start_idx on public.activities (type, start_time) where status = 'active';

-- ---------------------------------------------------------------------------
-- walk_routes
--   Public columns (labels + snapped geometry) are what discovery uses.
--   Protected columns (exact coordinates, route, meeting details) have no SELECT grant for clients:
--   they're only readable through get_private_activity_details() for the creator and accepted guests.
-- ---------------------------------------------------------------------------
create table public.walk_routes (
  id                    uuid primary key default gen_random_uuid(),
  activity_id           uuid not null unique references public.activities (id) on delete cascade,
  pace                  text not null check (pace in ('casual', 'moderate', 'fast')),
  public_start_location text not null check (char_length(public_start_location) between 1 and 60 and public_start_location !~ '^\d+\s'),
  public_end_location   text not null check (char_length(public_end_location) between 1 and 60 and public_end_location !~ '^\d+\s'),
  public_area           text not null,
  public_start_point    extensions.geography(Point, 4326)      not null,
  public_end_point      extensions.geography(Point, 4326)      not null,
  public_route_geometry extensions.geography(LineString, 4326) not null,
  -- protected ↓
  start_coordinates     extensions.geography(Point, 4326)      not null,
  end_coordinates       extensions.geography(Point, 4326)      not null,
  route_geometry        extensions.geography(LineString, 4326) not null,
  distance_meters       integer not null check (distance_meters between 50 and 20000),
  meeting_details       text not null default '' check (char_length(meeting_details) <= 200)
);
create index walk_routes_public_route_gix on public.walk_routes using gist (public_route_geometry);
create index walk_routes_public_start_gix on public.walk_routes using gist (public_start_point);
create index walk_routes_public_end_gix   on public.walk_routes using gist (public_end_point);
-- Exact geometry index: groundwork for future overlapping-route matching (not used by clients in this phase).
create index walk_routes_route_gix on public.walk_routes using gist (route_geometry);

-- ---------------------------------------------------------------------------
-- cowork_locations
-- ---------------------------------------------------------------------------
create table public.cowork_locations (
  id               uuid primary key default gen_random_uuid(),
  activity_id      uuid not null unique references public.activities (id) on delete cascade,
  work_style       text not null check (work_style in ('deep_work', 'social', 'build_together')),
  public_area      text not null,
  public_point     extensions.geography(Point, 4326) not null,
  -- protected ↓
  cafe_name        text not null check (char_length(btrim(cafe_name)) between 1 and 100),
  address          text check (char_length(address) <= 200),
  latitude         double precision not null check (latitude between -90 and 90),
  longitude        double precision not null check (longitude between -180 and 180),
  location         extensions.geography(Point, 4326)
                     generated always as (extensions.ST_SetSRID(extensions.ST_MakePoint(longitude, latitude), 4326)::extensions.geography) stored,
  place_identifier text check (char_length(place_identifier) <= 200),
  meeting_details  text not null default '' check (char_length(meeting_details) <= 200)
);
create index cowork_locations_public_gix on public.cowork_locations using gist (public_point);
create index cowork_locations_location_gix on public.cowork_locations using gist (location);

-- ---------------------------------------------------------------------------
-- join_requests (an accepted request IS the participation record)
-- ---------------------------------------------------------------------------
create table public.join_requests (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references public.activities (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger join_requests_set_updated_at before update on public.join_requests
  for each row execute function public.set_updated_at();
-- At most one *active* request per person per activity (history rows are allowed).
create unique index join_requests_one_active_idx on public.join_requests (activity_id, requester_id)
  where status in ('pending', 'accepted');
create index join_requests_requester_idx on public.join_requests (requester_id, status);
create index join_requests_activity_idx on public.join_requests (activity_id, status);

-- Defence in depth: nobody can request their own activity, even if a future code path forgets to check.
create or replace function private.reject_own_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.activities a where a.id = new.activity_id and a.creator_id = new.requester_id) then
    raise exception 'own_activity';
  end if;
  return new;
end $$;
create trigger join_requests_reject_own before insert on public.join_requests
  for each row execute function private.reject_own_request();

-- ---------------------------------------------------------------------------
-- conversations / participants / messages
-- ---------------------------------------------------------------------------
create table public.conversations (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index conversations_activity_idx on public.conversations (activity_id);

create table public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  joined_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_participants_user_idx on public.conversation_participants (user_id);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  content         text not null check (char_length(btrim(content)) between 1 and 2000),
  created_at      timestamptz not null default now()
);
-- Keyset pagination: (created_at desc, id desc) within a conversation.
create index messages_conversation_created_idx on public.messages (conversation_id, created_at desc, id desc);

-- ---------------------------------------------------------------------------
-- user_blocks
-- ---------------------------------------------------------------------------
create table public.user_blocks (
  blocker_id           uuid not null references public.profiles (id) on delete cascade,
  blocked_id           uuid not null references public.profiles (id) on delete cascade,
  blocked_display_name text,   -- snapshot taken at block time, because a blocked profile is no longer readable
  created_at           timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);
create index user_blocks_blocked_idx on public.user_blocks (blocked_id);
