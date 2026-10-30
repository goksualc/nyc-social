-- LOCAL TEST HARNESS ONLY — recreates the parts of a Supabase project that the migrations depend on.
-- Never run this against a real Supabase project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
grant anon, authenticated, service_role to postgres;
create role authenticator noinherit login password 'authpw';   -- PostgREST connects as this role and switches per request
grant anon, authenticated, service_role to authenticator;

create schema extensions;
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean default false,
                              file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language plpgsql immutable as $$
declare parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1:array_length(parts, 1) - 1];
end $$;

create publication supabase_realtime;

-- Supabase's default privileges: new objects in `public` are open to the API roles (migrations then lock them down).
grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
grant select on all tables in schema storage to authenticated;
grant insert, update, delete on storage.objects to authenticated;
grant execute on function auth.uid(), storage.foldername(text) to anon, authenticated, service_role;
