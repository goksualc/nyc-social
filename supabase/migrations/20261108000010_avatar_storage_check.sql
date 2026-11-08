-- Along · migration 10 — make sure profile-photo storage is complete (idempotent, never weakens anything)
--
-- Migration 5 already creates the private `avatars` bucket and its policies. This migration only fills in what is MISSING,
-- so it is safe whether or not migration 5 ran completely:
--   * the bucket is created only if absent (never duplicated, never loosened if it exists)
--   * each storage policy is created only if its name is absent
--   * the avatar_url column privileges the app needs are (re)granted to signed-in users only
--
-- Layout the app uses:  avatars/<user uuid>/avatar-<unix ms>.jpg   (2 MB limit; jpeg/png/webp)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars: read visible profiles') then
    create policy "avatars: read visible profiles" on storage.objects for select to authenticated
      using (bucket_id = 'avatars'
             and exists (select 1 from public.profiles p where p.id::text = (storage.foldername(name))[1]));   -- profiles RLS applies
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars: upload own folder') then
    create policy "avatars: upload own folder" on storage.objects for insert to authenticated
      with check (bucket_id = 'avatars'
                  and (storage.foldername(name))[1] = auth.uid()::text
                  and name ~ '^[0-9a-f-]{36}/avatar(-[0-9]+)?\.(jpg|jpeg|png|webp)$');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars: replace own') then
    create policy "avatars: replace own" on storage.objects for update to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
      with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars: delete own') then
    create policy "avatars: delete own" on storage.objects for delete to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
end $$;

-- The app changes the photo with a minimal `update profiles set avatar_url = …` for the signed-in user only
-- (the existing `profiles_update_own` row policy restricts it to their own row).
grant select (avatar_url), update (avatar_url) on public.profiles to authenticated;
