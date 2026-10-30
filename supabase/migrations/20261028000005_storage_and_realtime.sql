-- Along · migration 5 — avatar storage and Realtime

-- Private bucket: avatars are fetched with short-lived signed URLs, and SELECT is tied to profile visibility.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Layout: avatars/<user-uuid>/avatar-<timestamp>.jpg
create policy "avatars: read visible profiles" on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and exists (select 1 from public.profiles p where p.id::text = (storage.foldername(name))[1])   -- profiles RLS applies
  );

create policy "avatars: upload own folder" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f-]{36}/avatar(-[0-9]+)?\.(jpg|jpeg|png|webp)$'
  );

create policy "avatars: replace own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars: delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Realtime: only tables the app subscribes to. Realtime evaluates each table's RLS per subscriber, so
-- clients only receive rows they are allowed to SELECT.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.join_requests, public.messages,
                                                 public.activities, public.conversation_participants;
  end if;
end $$;
