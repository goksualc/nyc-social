-- Along · migration 6 — user reports (Report buttons in the app need somewhere real to go)
-- Clients can only INSERT through report_content(); nobody except the service role (moderation tooling) can read.

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('user', 'activity')),
  target_id   uuid not null,
  reason      text not null check (reason in ('inappropriate', 'unsafe', 'spam', 'other')),
  details     text check (char_length(details) <= 500),
  created_at  timestamptz not null default now()
);
create index reports_target_idx on public.reports (target_type, target_id);
create index reports_reporter_idx on public.reports (reporter_id, created_at desc);

alter table public.reports enable row level security;     -- no policies: unreachable for anon/authenticated
revoke all on public.reports from anon, authenticated;

create or replace function public.report_content(
  p_target_type text, p_target_id uuid, p_reason text, p_details text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_target_type not in ('user', 'activity') or p_reason not in ('inappropriate', 'unsafe', 'spam', 'other') then
    raise exception 'not_allowed';
  end if;
  -- crude abuse guard: 20 reports per rolling day
  if (select count(*) from public.reports where reporter_id = v_uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'rate_limited';
  end if;
  insert into public.reports (reporter_id, target_type, target_id, reason, details)
  values (v_uid, p_target_type, p_target_id, p_reason, left(p_details, 500));
end $$;

revoke all on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;
