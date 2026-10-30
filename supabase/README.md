# Along — Supabase backend

PostgreSQL + PostGIS + Row Level Security, with all writes going through validated `SECURITY DEFINER` functions.

## What's here

| File | Purpose |
|---|---|
| `migrations/…0001_extensions_and_geo.sql` | PostGIS, `private` schema, Manhattan boundary, neighbourhoods, public-grid snapping |
| `migrations/…0002_core_tables.sql` | `profiles`, `activities`, `walk_routes`, `cowork_locations`, `join_requests`, `conversations`, `conversation_participants`, `messages`, `user_blocks` + constraints, GiST/B-tree indexes, triggers |
| `migrations/…0003_security_helpers_and_rls.sql` | RLS on every table, column-level grants, private helper functions |
| `migrations/…0004_rpc_functions.sql` | `create_walk`, `create_cowork`, `update_activity`, `cancel_activity`, `request_to_join`, `respond_to_join_request` (row-locked, capacity-safe), `discover_activities` (bbox), `nearby_activities` (radius), `list_my_activities`, `get_private_activity_details`, `block_user`, profile + account RPCs |
| `migrations/…0005_storage_and_realtime.sql` | private `avatars` bucket + policies, Realtime publication |
| `migrations/…0006_reports.sql` | `reports` table + `report_content()` |
| `config.toml` | Supabase CLI config (Apple provider, exposed schemas) |
| `tests/` | Local test harness (see below) |

### Privacy model in one paragraph
Clients can **only read** the public columns of `walk_routes` / `cowork_locations` (labels and coordinates snapped to a ~250 m grid, computed
by the server). Exact coordinates, café name/address, route geometry and meeting notes have **no SELECT grant**; they're returned by
`get_private_activity_details()` to the creator and accepted guests only. Private plans are visible to their creator only. Blocks hide
profiles, plans, requests, chats and Realtime events in both directions. Nothing writes to `activities`, routes, locations,
requests or conversations except the RPCs (there are no INSERT/UPDATE policies, so direct writes are denied by default).

### Design notes
* An **accepted `join_request` is the participation record** (no separate participants table); remaining capacity = `max_participants − accepted`.
* Conversations are **1:1 between the host and one accepted guest**, matching the existing Inbox UI. `conversation_participants` can
  represent groups later.
* Additions to the requested schema: `profiles.age_confirmed_at` (server-set 18+ timestamp), `user_blocks.blocked_display_name`
  (a blocked profile is no longer readable, so the Blocked Users list needs a snapshot), public-geometry columns on the route/location
  tables, `pace` / `work_style` / `meeting_details`, and the `reports` table.
* Guests learn about edits and cancellations through their own (RLS-scoped) `join_requests` rows — the RPCs touch them — so no client
  subscribes to every activity in Manhattan.

## Deploy to a Supabase project

1. Create a project at supabase.com (note the **Project URL** and **publishable key** under *Project Settings → API*).
2. Apply the migrations, in order:
   ```sh
   npx supabase login
   npx supabase link --project-ref <your-project-ref>
   npx supabase db push
   ```
   (or paste each file into the SQL editor in numeric order). PostGIS is created in the `extensions` schema.
3. **Auth → Providers → Apple**: enable it and add your bundle id (`com.along.app`) to *Authorized Client IDs*.
4. In the iOS app:
   ```sh
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # git-ignored
   # edit it: SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY — never the secret / service-role key
   xcodegen generate
   ```
   Without this file the app runs in **demo mode** (local data) and says so in *Profile → About Along*.
5. In Xcode, set your Development Team and make sure the **Sign in with Apple** capability is enabled for the App ID.

## Tests

Requires Docker.
```sh
supabase/tests/run_local.sh          # applies all migrations to a throwaway PostGIS, runs ~137 SQL checks + a concurrency race
supabase/tests/run_integration.sh    # + PostgREST: drives the real Swift services as three accounts on the iOS Simulator
```
`run_local.sh` covers RLS and column privileges, location privacy, discovery filters/pagination, request/accept/decline/cancel/leave,
capacity under 8 concurrent approvals, chat gating, blocking in both directions, storage policies, reports and account deletion.
The harness stubs the pieces a Supabase project provides (`auth.uid()`, roles, `storage`) in `tests/00_supabase_stubs.sql` — never run that file against a real project.

## Remaining manual steps / not covered by the automated tests

* **Realtime and Storage were not exercised end to end** (the harness has no Realtime server or object store). The publication, bucket and
  policies are created by the migrations and policy-tested in SQL; verify live delivery of new requests/messages and avatar upload on a real project.
* **Sign in with Apple** needs a real device/Apple ID and a configured project. The nonce handling is implemented (hashed to Apple, raw to Supabase).
* **Account deletion & Apple**: `delete_my_account()` removes the user and all owned data. App Store guideline 5.1.1(v) also expects the
  Apple token to be revoked; that needs your Apple private key, so do it in an Edge Function (not in the app).
* **Completed plans**: past plans disappear from discovery by `end_time`. To also flip their `status` to `completed`, schedule
  `select public.mark_completed_activities();` with `pg_cron` or a scheduled Edge Function (service role only).
* **Abuse controls**: reports are stored (20/day cap) but there's no moderation tooling, rate limiting on requests/messages, captcha or
  age assurance beyond a self-declaration. Add before a public launch.
* **SDK version**: `supabase-swift` is pinned to 2.49.0 because 2.50+ needs Swift tools 6.1 (Xcode 16.3+). Raise `exactVersion` in `project.yml` after upgrading Xcode.
* After adding new public functions, re-run the grant block at the end of migration 4 (or add explicit `grant execute` / `revoke … from anon`).
