-- Along · migration 8 — detailed social profiles and onboarding state
--
-- Additive only. Existing profile data is preserved; legacy columns (`interests`, `looking_for`) stay in place.
-- Does not modify any earlier migration. Run once, after migration 7.

-- ---------------------------------------------------------------------------
-- 1. New profile fields (all optional, none sensitive; no home addresses anywhere)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists instagram_username  text check (instagram_username ~ '^[A-Za-z0-9._]{1,30}$'),
  add column if not exists x_username          text check (x_username ~ '^[A-Za-z0-9_]{1,15}$'),
  add column if not exists occupation          text check (char_length(occupation) between 1 and 60),
  add column if not exists university          text check (char_length(university) between 1 and 80),
  add column if not exists languages           text[] not null default '{}' check (cardinality(languages) <= 8),
  add column if not exists hobbies             text[] not null default '{}' check (cardinality(hobbies) <= 30),
  add column if not exists conversation_custom text[] not null default '{}' check (cardinality(conversation_custom) <= 3),
  add column if not exists preferred_duration  smallint check (preferred_duration in (15, 30, 45, 60)),
  add column if not exists favorite_mode       text check (favorite_mode in ('just_walk', 'overthink', 'both')),
  add column if not exists birthday            date,                       -- private: never readable by other users
  add column if not exists show_age            boolean not null default false,
  add column if not exists show_walk_stats     boolean not null default false,
  add column if not exists onboarding_completed boolean not null default false;

-- Slow joins the preferred paces; the favourite-neighbourhood limit grows to 10. (Constraint names are looked up, not assumed.)
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.profiles'::regclass and contype = 'c'
             and (pg_get_constraintdef(oid) like '%preferred_pace%' or pg_get_constraintdef(oid) like '%favorite_neighborhoods%')
  loop
    execute format('alter table public.profiles drop constraint %I', c);
  end loop;
  alter table public.profiles add constraint profiles_preferred_pace_check check (preferred_pace in ('slow', 'casual', 'moderate', 'fast'));
  alter table public.profiles add constraint profiles_favorite_neighborhoods_check check (cardinality(favorite_neighborhoods) <= 10);
end $$;

-- Hobbies: copy the legacy interests once so nobody loses their tags.
update public.profiles
   set hobbies = (select coalesce(array_agg(initcap(x)), '{}') from unnest(interests) x)
 where cardinality(hobbies) = 0 and cardinality(interests) > 0;

-- Anyone whose profile was already complete does not repeat onboarding.
update public.profiles set onboarding_completed = true
 where display_name is not null and age_confirmed_at is not null and not onboarding_completed;

-- Birthday is optional, but when given it must describe an adult (the 18+ rule is enforced server-side).
create or replace function private.validate_profile_birthday()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.birthday is not null and (new.birthday > current_date - interval '18 years' or new.birthday < date '1900-01-01') then
    raise exception 'invalid_birthday';
  end if;
  return new;
end $$;
drop trigger if exists profiles_validate_birthday on public.profiles;
create trigger profiles_validate_birthday before insert or update of birthday on public.profiles
  for each row execute function private.validate_profile_birthday();

-- ---------------------------------------------------------------------------
-- 2. Column privileges: everything is readable by people allowed to see the profile EXCEPT birthday
-- ---------------------------------------------------------------------------
grant select (instagram_username, x_username, occupation, university, languages, hobbies, conversation_custom,
              preferred_duration, favorite_mode, show_age, show_walk_stats, onboarding_completed)
  on public.profiles to authenticated;
grant update (instagram_username, x_username, occupation, university, languages, hobbies, conversation_custom,
              preferred_duration, favorite_mode, birthday, show_age, show_walk_stats, preferred_pace, favorite_neighborhoods)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 3. get_my_profile now returns the whole own profile (including private birthday and onboarding state)
-- ---------------------------------------------------------------------------
drop function if exists public.get_my_profile();
create or replace function public.get_my_profile()
returns table (id uuid, username text, full_name text, display_name text, bio text, avatar_url text,
               interests text[], looking_for text[], visibility text, age_confirmed_at timestamptz,
               created_at timestamptz, updated_at timestamptz,
               favorite_neighborhoods text[], preferred_pace text, discussion_topics text[],
               instagram_username text, x_username text, occupation text, university text, languages text[],
               hobbies text[], conversation_custom text[], preferred_duration smallint, favorite_mode text,
               birthday date, show_age boolean, show_walk_stats boolean, onboarding_completed boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select p.id, p.username, p.full_name, p.display_name, p.bio, p.avatar_url, p.interests, p.looking_for,
           p.visibility, p.age_confirmed_at, p.created_at, p.updated_at,
           p.favorite_neighborhoods, p.preferred_pace, p.discussion_topics,
           p.instagram_username, p.x_username, p.occupation, p.university, p.languages,
           p.hobbies, p.conversation_custom, p.preferred_duration, p.favorite_mode,
           p.birthday, p.show_age, p.show_walk_stats, p.onboarding_completed
    from public.profiles p where p.id = auth.uid();
end $$;

-- Ages only for people who chose to show theirs (and whose profile the caller may see). Never the birthday itself.
create or replace function public.profile_ages(p_ids uuid[])
returns table (id uuid, age integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
    select p.id, extract(year from age(current_date, p.birthday))::integer
    from public.profiles p
    where p.id = any (p_ids) and p.birthday is not null
      and (p.id = auth.uid()
           or (p.show_age and not private.blocked_with(p.id) and (p.visibility = 'everyone' or private.shares_context(p.id))));
end $$;

-- Marks onboarding as finished (display name and the 18+ confirmation must already be on the profile).
create or replace function public.complete_onboarding()
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ok boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select (display_name is not null and age_confirmed_at is not null) into v_ok from public.profiles where id = v_uid;
  if not coalesce(v_ok, false) then raise exception 'profile_incomplete'; end if;
  update public.profiles set onboarding_completed = true where id = v_uid;
end $$;

revoke all on function public.get_my_profile(), public.profile_ages(uuid[]), public.complete_onboarding() from public, anon;
grant execute on function public.get_my_profile(), public.profile_ages(uuid[]), public.complete_onboarding() to authenticated;
