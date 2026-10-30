# Along (iOS)

"Good company, wherever you're headed." A Manhattan-only app for finding someone to walk or cowork with.

## Run
```
brew install xcodegen      # once
xcodegen generate          # creates Along.xcodeproj from project.yml
open Along.xcodeproj       # iOS 17+, run the Along scheme
```
**Two modes.** With `Config/Secrets.xcconfig` (Supabase URL + publishable key) the app is live: Sign in with Apple, real data, realtime.
Without it the app runs in **demo mode** on local data, exactly like the original prototype. See [supabase/README.md](supabase/README.md) for backend setup.
Tests: `xcodebuild test -scheme Along -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` (unit tests; the live integration test skips itself),
`supabase/tests/run_local.sh` (SQL/RLS/concurrency) and `supabase/tests/run_integration.sh` (real PostgREST + Swift services, needs Docker).

## Architecture
SwiftUI + MVVM, `@Observable`, async/await, iOS 17.
- `Models/` Codable, Sendable value types (ready to map to Supabase tables).
- `Services/AlongBackend.swift` service protocols: `AuthService`, `ProfileService`, `ActivityService`, `JoinRequestService`, `MessagingService`, `StorageService`, `SafetyService`, `RealtimeService`. `Services/Supabase/` implements them against Supabase; `MockAlongBackend` implements the data services in memory for demo mode and tests.
- `App/AppSession.swift` owns auth state (`launching → signedOut | needsProfile | ready`) and the signed-in `AppStore`.
- `Core/AppStore.swift` mirrors the user's `AlongSnapshot`, a map-bounded page of public discovery results, and realtime events. Every mutation goes through the backend; failures become short friendly messages (`ErrorPresenter`).
- `Features/*` a view + view model per screen. `Components/` and `DesignSystem/` hold reusable UI and tokens.
- `Core/SafetyPolicy.swift` lists what is simulated vs. what must be server-enforced (also shown in Profile → About Along).

## Debug launch arguments (DEBUG builds)
`-along-skip-onboarding -along-tab 0..3 -along-detent half|full -along-select <id> -along-open <id> -along-create walk|cowork -along-conversation <id>`
Demo ids: `act-midtown act-chelsea act-park act-east act-battery act-soho act-flatiron act-westvillage act-eastvillage`, chats `conv-priya conv-jonas`.

## Brand assets
`tools/make_logo_assets.py` extracts transparent logos from the two supplied images (alpha mask only; artwork is never redrawn).
