# Along — Phase 1 (iOS prototype)

"Good company, wherever you're headed." A Manhattan-only app for finding someone to walk or cowork with.

## Run
```
brew install xcodegen      # once
xcodegen generate          # creates Along.xcodeproj from project.yml
open Along.xcodeproj       # iOS 17+, run the Along scheme
```
First launch shows the splash → welcome → 18+ check. "I already have an account" loads the local demo profile.
Tests: `xcodebuild test -scheme Along -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.

## Architecture
SwiftUI + MVVM, `@Observable`, async/await, iOS 17.
- `Models/` Codable, Sendable value types (ready to map to Supabase tables).
- `Services/AlongBackend.swift` protocols (Auth, Activity, Request, Messaging, Profile, Safety, Demo). `MockAlongBackend` (an actor) implements them in memory, **including the rules a server must enforce** (spot limits, blocking, redaction, chat gating). Swap in a Supabase-backed type conforming to `AlongBackend`; no UI changes needed.
- `Core/AppStore.swift` mirrors the latest `AlongSnapshot` and exposes derived queries. Every mutation goes through the backend.
- `Features/*` a view + view model per screen. `Components/` and `DesignSystem/` hold reusable UI and tokens.
- `Core/SafetyPolicy.swift` lists what is simulated vs. what must be server-enforced (also shown in Profile → About Along).

## Debug launch arguments (DEBUG builds)
`-along-skip-onboarding -along-tab 0..3 -along-detent half|full -along-select <id> -along-open <id> -along-create walk|cowork -along-conversation <id>`
Demo ids: `act-midtown act-chelsea act-park act-east act-battery act-soho act-flatiron act-westvillage act-eastvillage`, chats `conv-priya conv-jonas`.

## Brand assets
`tools/make_logo_assets.py` extracts transparent logos from the two supplied images (alpha mask only; artwork is never redrawn).
