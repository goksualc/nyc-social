# Along (iOS)

> **"Good company, wherever you're headed."**
> Walk together. Overthink together.

Along is a social walking app for **New York City**. Someone posts a walk (where from, where to, when, how fast), other people
find it on a map and ask to join, and once a request is accepted the two of them can chat, meet, and walk — with a live walk
screen, a completion flow and a walk history.

It is an iOS 17+ SwiftUI app backed by **Supabase** (Postgres + PostGIS + Row Level Security + Realtime + Storage). It also ships
a complete **demo mode** that runs entirely on local data, so you can explore every screen without a backend.

---

## Table of contents

1. [What the app does](#what-the-app-does)
2. [Screens and features](#screens-and-features)
3. [Getting started](#getting-started)
4. [Project layout](#project-layout)
5. [Architecture](#architecture)
6. [Backend (Supabase)](#backend-supabase)
7. [Privacy and safety model](#privacy-and-safety-model)
8. [Design system](#design-system)
9. [Testing](#testing)
10. [Debug launch arguments](#debug-launch-arguments)
11. [Brand and artwork assets](#brand-and-artwork-assets)
12. [Known gaps and manual steps](#known-gaps-and-manual-steps)
13. [Related docs](#related-docs)

---

## What the app does

- **One kind of activity: a Walk.** (Earlier prototypes had "Just Walk", "Overthink Together" and "Cowork"; these were unified.
  Old database columns remain for compatibility, but nothing new writes them.)
- **Discover on a map.** Walks appear as markers and numbered clusters over all five boroughs. Tapping a marker or cluster
  opens a bottom sheet of walk cards.
- **Search by route.** Type where you are walking from/to and Along finds public walks that run *along* your route, ranked by
  overlap, proximity, direction, time and open spots — all measured server-side with PostGIS.
- **Host a walk** in three identity modes: **Public**, **Private Host** and **Anonymous Host**, with optional topic tags and a
  free-text "What's on your mind?".
- **Request, accept, chat.** Join requests are accepted or declined by the host. Accepted pairs get a one-to-one chat.
- **Walk together.** A live walk flow (ready check → active → completion) shares position only between the two walkers, only
  during the walk, and never stores it.
- **Stay safe.** Approximate public locations, exact details only after acceptance, block/report, 18+ confirmation.

---

## Screens and features

### First launch tutorial
An 8-page tutorial is shown **once per device**, before the landing page:

| Page | Content |
|---|---|
| 0 | Welcome: navy background, flower bouquet top-right, yellow tile ornament rising from the bottom, **Show Me Around** / **Skip for Now** |
| 1–6 | Feature pages with drawn (not screenshot) previews: Explore, Route search, Create, Walk card, Live walk, Memories |
| 7 | Closing: "You're officially Along." with yellow ornament frames, **Find Your First Walk**, **Back** |

Implementation: `Features/Onboarding/IntroTutorialView.swift` and `IntroPreviews.swift`. The flag lives in `@AppStorage`
(`along.hasSeenIntroTutorial`). Installs that already have a session or older onboarding flags are migrated so existing users
never see it. The first and last pages hide the status bar's dark style via a small `ChromeStyle` environment object so the
clock/battery stay legible on navy.

### Landing, auth and profile setup
- **Landing page** with the "Iznik" tile artwork and Slash display type (`WelcomeView`, `IznikArt`, `SplashView`).
- **Authentication:** email + password (with email verification and password reset) and **Google** (Supabase OAuth, PKCE,
  `ASWebAuthenticationSession`). Sign in with Apple and phone/SMS sign-in were built and later **removed** from the app.
- **Profile setup** (`OnboardingFlowView`): name, bio, 18+ confirmation, interests, Instagram/X handles, preferred pace and
  duration, favourite neighbourhoods, conversation topics.
- **Demo sign-in** is available only when no Supabase config is present.

### Explore (tab 1 — the map)
- MapKit map with approximate walk markers, clustering into numbered circles, and location permission handling.
- **Cluster tap** opens a horizontally paged stack of identical walk cards (`ActivityPreviewCard`), all the same height; the
  selected walk stays highlighted on the map. Single-walk and multi-walk locations use *exactly the same card design*.
- Drag the card down to dismiss; a sideways swipe pages between walks.
- Search bar for places (`PlaceSearch`, NYC-restricted) and for route search (`RouteSearch.swift`).
- Filters/pills, empty states, toasts.

### Create a walk (centre button of the floating bar)
`Features/CreateActivity/*`
- Pick a start and end place (NYC only — the five boroughs); route preview line on a map.
- Date/time, duration, capacity, pace (Casual / Moderate / Fast).
- **Host mode:** *Public* (your profile is shown), *Private Host* (on the map, identity hidden, tags shown), *Anonymous Host*
  (identity hidden and minimal details).
- **"What's on your mind?"** — an optional free-text prompt (max 140 chars), never a category.
- **Tags:** 1–3 optional topic tags (e.g. Tech, Career, Random Thoughts).
- A live **summary card** shows how the walk will look before publishing.

### Plans (tab 2)
Hosted and requested walks, request status (pending / accepted / declined / withdrawn), cancel / leave, access to walk
history and the live walk flow.

### Chat (tab 3, formerly "Inbox")
- One-to-one conversations between the host and an accepted guest.
- Conversation list with a **working search**, a composer pinned with `safeAreaInset`, and the floating tab bar hidden only
  inside a conversation.
- Chats close when the walk is cancelled or the guest leaves.

### Profile (tab 4)
Detailed social profile (occupation, university, languages, handles, topics), editable photo (stored in a private bucket),
settings, blocked users, About Along (shows what is simulated vs. server-enforced and whether you are in demo mode), sign out and
**account deletion**.

### Live walk
`Features/LiveWalk/*` — ready screen, live map with both walkers' positions, completion and history. The session is a
server-authoritative state machine (see [Backend](#backend-supabase)).

### Floating glass tab bar
A custom bar (Map · Plans · ＋ · Chat · Profile) replaces the system tab bar. Non-map pages reserve 84 pt of bottom inset so
content never hides behind it. A badge shows incoming pending requests.

---

## Getting started

### Requirements
- macOS with **Xcode 16+** (the Supabase Swift SDK is pinned to **2.49.0**; 2.50+ needs Xcode 16.3 / Swift tools 6.1)
- iOS 17.0+ simulator or device
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Docker (only for the SQL/integration tests)

### Run
```sh
brew install xcodegen      # once
xcodegen generate          # creates Along.xcodeproj from project.yml
open Along.xcodeproj       # run the "Along" scheme
```
`Along.xcodeproj` is generated and git-ignored. Re-run `xcodegen generate` after adding/removing files or changing `project.yml`.

### Two modes
| Mode | When | What you get |
|---|---|---|
| **Live** | `Config/Secrets.xcconfig` exists with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` | Real accounts, real data, Realtime, Storage |
| **Demo** | No secrets file | Local seeded data (`SeedData.swift`) in `MockAlongBackend`; *Profile → About Along* says so |

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # git-ignored
# fill in SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY — the publishable (anon) key only, NEVER the service-role/secret key
xcodegen generate
```
xcconfig treats `//` as a comment, so URLs are written `https:/$()/your-project.supabase.co`.

Optional `LEGAL_TERMS_URL` / `LEGAL_PRIVACY_URL` in `Config/Base.xcconfig` link real Terms/Privacy pages; if empty they are shown
as plain text, never as links.

In Xcode set your Development Team (a free Personal Team works — the app uses no restricted capabilities). The app registers the
URL scheme `com.along.app` for auth redirects.

---

## Project layout

```
nyc-social/
├── project.yml                 xcodegen spec (targets, fonts, Info.plist keys, SPM packages)
├── Config/                     Base/Debug/Release/Secrets .xcconfig (+ .example)
├── Along/
│   ├── App/                    AlongApp, RootView, AppSession, MainTabView
│   ├── Core/                   AppStore, NYCGeo, LocationService, PlaceSearch, RouteService,
│   │                           WalkLocationTracker, ErrorPresenter, LaunchOptions, ActivityTime, NetworkMonitor …
│   ├── Models/                 Activity, User, Profile, Place, Coordinate, WalkSession, Snapshot,
│   │                           RouteSearchModels, AlongError
│   ├── Services/
│   │   ├── AlongBackend.swift  service protocols (the seam between UI and data)
│   │   ├── MockAlongBackend    in-memory implementation (demo mode + tests)
│   │   ├── DemoAuthService, SeedData, SafetyPolicy, AuthRedirect
│   │   └── Supabase/           real implementations: Config, DTOs, Services, WalkServices,
│   │                           SnapshotLoader, RealtimeService, Support
│   ├── Features/               one folder per screen area (view + view model)
│   │   ├── Onboarding/  Auth/  Explore/  CreateActivity/  ActivityDetails/
│   │   └── Plans/  Inbox/ (Chat)  LiveWalk/  Profile/
│   ├── Components/             reusable UI (cards, buttons, avatar, map marker, toast, logo …)
│   ├── DesignSystem/           tokens (colour, spacing, type), styles, display heading type
│   ├── Assets/                 asset catalog (logo, Iznik art, tutorial artwork)
│   └── Resources/              fonts (Slash, Roboto), Info.plist (generated)
├── AlongTests/                 XCTest unit tests (see Testing)
├── supabase/
│   ├── migrations/             15 versioned SQL migrations (never edit a deployed one — add a new one)
│   ├── tests/                  SQL + integration harness
│   ├── config.toml             Supabase CLI config
│   └── README.md               backend deep dive
├── tools/make_logo_assets.py   logo extraction script
├── public/                     fonts and source images (paint textures used for artwork)
└── docs-auth.md                Google / email auth provider setup
```

---

## Architecture

SwiftUI + **MVVM**, `@Observable`, `async/await`, iOS 17, Swift 5 language mode.

```
View ──▶ ViewModel (@Observable) ──▶ AppStore ──▶ service protocols ──▶ SupabaseServices  (live)
                                                                      └─▶ MockAlongBackend  (demo/tests)
```

- **Models** (`Models/`) are `Codable`, `Sendable` value types.
- **Service protocols** (`Services/AlongBackend.swift`): `AuthService`, `ProfileService`, `ActivityService`,
  `JoinRequestService`, `MessagingService`, `StorageService`, `SafetyService`, `RealtimeService`. Mutations that change "my
  world" return a fresh `AlongSnapshot`; discovery is queried separately.
- **`AppSession`** owns auth state (`launching → signedOut | emailVerification | passwordRecovery | needsProfile | ready |
  failed`) and creates the signed-in `AppStore`.
- **`AppStore`** mirrors the user's snapshot, a map-bounded page of public discovery results, and realtime events. Every
  mutation goes through the backend; failures are converted into short friendly messages by `ErrorPresenter`.
- **DTOs** (`SupabaseDTOs.swift`): rows exactly as PostgREST returns them (snake_case → camelCase via a shared decoder) with
  mapping into domain models. RPC parameter structs encode camelCase `pFoo` → `p_foo`.
- **Realtime:** join-request changes, `chat_pings` for new messages, and a private broadcast channel per live walk session.
- **Navigation:** `AlongRoute` (`.activity(id)`, `.conversation(id)`) with a `NavigationStack`; a `TabChrome` object lets chat
  hide the floating bar; `ChromeStyle` toggles the status-bar colour scheme for the dark tutorial pages.
- **Location:** `LocationService` (when-in-use), `RouteService` (MapKit walking routes), `WalkLocationTracker` (live walks only).
- **Geography:** `NYCGeo` holds the five-borough rules and gazetteer used client-side; the server is the authority.
- **Safety:** `SafetyPolicy` documents what demo mode simulates vs. what the database enforces (also shown in-app).

---

## Backend (Supabase)

PostgreSQL + **PostGIS** + **RLS**. Clients read only public columns; every write goes through validated `SECURITY DEFINER`
functions (RPCs). Full details are in [supabase/README.md](supabase/README.md).

### Migrations

| # | File | Purpose |
|---|---|---|
| 1 | `extensions_and_geo` | PostGIS, `private` schema, geo regions, neighbourhood labels, public-grid snapping |
| 2 | `core_tables` | `profiles`, `activities`, `walk_routes`, `cowork_locations`, `join_requests`, `conversations`, `conversation_participants`, `messages`, `user_blocks` |
| 3 | `security_helpers_and_rls` | RLS on every table, column-level grants, private helpers |
| 4 | `rpc_functions` | create/update/cancel, request/respond (row-locked, capacity-safe), discover (bbox), nearby (radius), private details, blocking, account RPCs |
| 5 | `storage_and_realtime` | private `avatars` bucket and policies, Realtime publication |
| 6 | `reports` | `reports` table and `report_content()` |
| 7 | `walk_modes` | walk modes (later unified) |
| 8 | `detailed_profiles` | Instagram/X, occupation, university, languages, pace, favourite neighbourhoods, topics |
| 9 | `walk_sessions` | live-walk state machine, readiness, completion, history, Realtime authorization |
| 10 | `avatar_storage_check` | avatar path validation |
| 11 | `anonymous_hosts_and_request_chat` | anonymous organizers (opaque `anon:` aliases), chat before acceptance, column revokes |
| 12 | `route_search` | "Where are you walking?" corridor matching with PostGIS |
| 13 | `unified_walks` | one kind of walk; `mind_prompt`; `create_walk` redefined |
| 14 | `nyc_coverage` | all five boroughs; `is_in_manhattan`/`is_near_manhattan` now mean "New York City" |
| 15 | `walk_tags` | up to 3 topic tags on every walk (stored in `host_interests`) |

> Rule of the repo: **never edit a migration that has been deployed.** Add a new numbered file. Do not weaken RLS.
> Migrations 7–15 must be applied to your Supabase project before the matching app features work against it.

### Key RPCs (non-exhaustive)
`create_walk`, `update_activity`, `cancel_activity`, `request_to_join`, `respond_to_join_request`, `discover_activities`,
`nearby_activities`, `search_walks_along_route`, `list_my_activities`, `get_private_activity_details`,
`list_my_conversations`, `list_my_messages`, `send_message`, `block_user`, `report_content`, `delete_my_account`, plus the
walk-session transitions (ready, start, complete, end early).

### Walk session state machine
```
awaiting_participants → ready_to_start → active → awaiting_completion → completed
        └───────────────┴──────────────┴──────────────┴──→ cancelled | ended_early | expired
```
Phase 1 is exactly two people (host + one accepted buddy). Live positions are never stored; they travel over a private Realtime
broadcast channel `walk:<session id>`.

### Geography
Locations are validated against the **five boroughs' outlines** (`private.geo_regions`, `ST_Covers`). Public labels use
neighbourhood names; coordinates shown to everyone are snapped to a ~250 m grid computed by the server.

### Route search
The client sends the MapKit walking route as `[lng, lat]` points. The server finds candidates with the spatial index and returns
per-walk `overlap_pct`, `route_distance_m`, `direction_diff_deg`, `starts_near`, `ends_near` and a combined `score`, using each
walk's **public** geometry only. Blocked and hidden hosts are excluded; anonymous organizers stay masked.

### Deploy
```sh
npx supabase login
npx supabase link --project-ref <your-project-ref>
npx supabase db push        # or paste each migration into the SQL editor in numeric order
```
Then configure `Config/Secrets.xcconfig` (see [Getting started](#getting-started)) and the auth redirect URLs in
[docs-auth.md](docs-auth.md).

---

## Privacy and safety model

| Protection | How it works |
|---|---|
| Approximate public locations | Public cards/map receive coordinates snapped to a ~250 m grid; exact coordinates, route geometry and meeting notes have **no SELECT grant** |
| Details after acceptance | `get_private_activity_details()` returns exact places and instructions to the host and accepted guests only |
| Anonymous / Private Host | Name, photo and id are replaced by an opaque `anon:` alias for everyone except the organizer; no profile can be looked up from it |
| Message gating | Chats exist only between the host and an accepted guest (or the host-initiated pre-acceptance flow) and close on leave/cancel |
| Blocking | Hides profiles, walks, requests, chats and Realtime events in **both** directions |
| Reports | `reports` table with a daily cap |
| 18+ | Self-declared at onboarding, stored with a server timestamp |
| NYC only | Server-side polygon checks, not just client checks |
| Writes | No INSERT/UPDATE policies — direct table writes are denied; only RPCs mutate |
| Live location | Shared only between the two walkers during an active session; never persisted |
| Secrets | Only the publishable key is in the app; service-role keys never are |

---

## Design system

- **Palette:** navy `#1C2343`, off-white `#FAF9F6`, white, and a **lime** accent. Tutorial bookend pages use a deeper navy
  (`#131832`) and lime `#B5F36E`.
- **Type:** *Roboto* (Regular/Medium/Bold) for headings only; SF Pro for body text, buttons and fields; *Slash Signature* for the
  landing/onboarding display face. All use `Font.custom(…, relativeTo:)` so Dynamic Type works. Font files are in
  `Along/Resources/Fonts` and registered through `UIAppFonts` in `project.yml`.
- **Components:** floating glass tab bar, bottom sheets, filter pills, chips and `FlowLayout`, profile avatars (with tone
  fallback), toasts, empty states, press styles, haptics.
- **Principles:** keep the Along logo/branding intact, minimum 44 pt touch targets, accessibility labels on icon-only controls.

---

## Testing

### Swift unit tests
```sh
xcodebuild test -scheme Along -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
The live integration test skips itself when there is no backend.

| Test file | Covers |
|---|---|
| `AuthFlowTests` | sign-in/up, verification, recovery, redirects |
| `AvatarFlowTests` | photo upload path and profile independence |
| `BackendRulesTests` | city boundary, gazetteer, request/capacity rules |
| `BackendServicesTests` | mock backend services |
| `ChatSearchTests` | conversation search |
| `IntroTutorialTests` | first-launch tutorial rules (`IntroTutorialRules`) |
| `ProfileAndWalkTests` | profile + walk behaviour |
| `RouteSearchTests` | route search, cluster sheet, create-walk form |
| `ScreensLogicTests` | view-model logic |
| `PlaceSearchPerformanceTests`, `TypingPerformanceTests` | responsiveness |
| `LiveBackendIntegrationTests` | real PostgREST + Swift services (needs setup) |

### SQL / backend tests (Docker)
```sh
supabase/tests/run_local.sh        # all migrations on a throwaway PostGIS; RLS, privileges, concurrency race
supabase/tests/run_new_tests.sh    # newer suites: 30 anonymous/request chat · 40 route search · 50 NYC coverage
                                   #                60 walk tags · 70 client read path
supabase/tests/run_integration.sh  # + PostgREST: real Swift services as three accounts on the simulator
```
`10_rls_and_rpc_tests.sql` predates the walk-only pivot and still calls the retired `create_cowork`, so the newer suites run via
`run_new_tests.sh`. `00_supabase_stubs.sql` fakes `auth.uid()`, roles and `storage` — **never run it against a real project**.

> These tests ran against a local PostGIS container, not against a live Supabase project.

---

## Debug launch arguments

DEBUG builds only. Pass them in the scheme's *Arguments* or via `simctl launch`.

| Argument | Effect |
|---|---|
| `-along-skip-onboarding` | skip profile onboarding |
| `-along-onboarding` | force onboarding |
| `-along-tab 0..3` | open a tab |
| `-along-detent half\|full` | card detent |
| `-along-select <id>` | select a walk on the map |
| `-along-open <id>` | open a walk's detail |
| `-along-create walk` | open the create flow |
| `-along-conversation <id>` | open a chat |
| `-along-inbox <filter>` | chat/inbox filter |
| `-along-cluster` | open the first numbered cluster's cards |
| `-along-intro` `-along-intro-page N` | show the tutorial (optionally at page N) without touching the saved flag |
| `-along-welcome-step <step>` | jump within the welcome flow |
| `-along-live` | live-walk screen |
| `-along-ready` | ready-state helper |

Demo ids: `act-midtown act-chelsea act-park act-east act-battery act-soho act-flatiron act-westvillage act-eastvillage`;
chats `conv-priya conv-jonas`.

---

## Brand and artwork assets

- `tools/make_logo_assets.py` extracts transparent logos from the supplied images (alpha mask only; artwork is never redrawn).
- Tutorial artwork (`IntroBouquet`, `IntroOrnament`, `IntroFrameTop`, `IntroFrameBottom`) was cropped from the supplied design
  screenshots with alpha keyed to the navy background; it is therefore somewhat soft when scaled. Higher-resolution cut-outs
  would make it pixel-exact.
- `public/images/*-paint.jpg` are the source tile/paint textures; `public/fonts` holds the font sources.

---

## Known gaps and manual steps

- **Not yet built in the client UI:** the "Anonymous Walker" reveal/block experience for organizers, and the
  *Accept | Message | Decline* pre-acceptance chat UI with its banner (the database side, e.g. `start_request_conversation`, exists).
- **Realtime and Storage** were not exercised end to end in automated tests; verify live delivery and avatar upload on a real project.
- **Migrations 7–15** need to be applied to your live Supabase project.
- **Account deletion** removes the user and owned data; any third-party token revocation would need an Edge Function.
- **Completed plans:** schedule `select public.mark_completed_activities();` (pg_cron or a scheduled Edge Function) to flip status.
- **Abuse controls:** reports are stored, but there is no moderation tooling, request/message rate limiting, captcha or
  age assurance beyond self-declaration — add before a public launch.
- **Devices:** the app has been checked in the simulator, not on a range of physical devices or small iPhones.
- **SDK pin:** raise `exactVersion` in `project.yml` once you move to Xcode 16.3+.
- After adding public functions, add explicit `grant execute` / `revoke … from anon`.

---

## Related docs

- [supabase/README.md](supabase/README.md) — schema, privacy model, deploy and test details
- [docs-auth.md](docs-auth.md) — Google/email provider and redirect URL setup
