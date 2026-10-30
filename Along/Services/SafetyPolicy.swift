import Foundation

/// A single place that documents how safety is handled.
///
/// Demo mode *simulates* these protections locally so the experience can be explored without a backend. With
/// Supabase connected they are enforced by Row Level Security and database functions (see `supabase/migrations`).
/// `requiredBeforeProduction` lists the items that still need operational work beyond the schema.
enum SafetyPolicy {
    struct Item: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let detail: String
    }

    static let simulatedInPrototype: [Item] = [
        .init(title: "Approximate public locations", detail: "Public cards and the map only receive coordinates snapped to a ~250 m grid."),
        .init(title: "Meeting details after acceptance", detail: "Exact places and instructions are withheld until a request is accepted."),
        .init(title: "Message gating", detail: "Chats only exist for accepted guests and close if they leave or the plan is cancelled."),
        .init(title: "Block and report", detail: "Blocking hides people from discovery, requests and chats. Reports are stored locally."),
        .init(title: "Expired plans", detail: "Plans disappear from the map when they end."),
        .init(title: "18+ confirmation", detail: "A self-declared checkbox during onboarding."),
        .init(title: "Manhattan only", detail: "Locations are checked against an approximate island boundary."),
    ]

    static let requiredBeforeProduction: [Item] = [
        .init(title: "Row Level Security", detail: "Users can only read or change what they own or have been granted. Writes go through validated functions."),
        .init(title: "Server-side redaction", detail: "Exact locations and meeting notes are only returned to the host and accepted guests."),
        .init(title: "Blocking everywhere", detail: "Blocks hide profiles, plans, requests and chats in both directions, including Realtime."),
        .init(title: "Verified age and identity", detail: "Today 18+ is a self-declaration stored with a server timestamp. Add age assurance before wide launch."),
        .init(title: "Moderation pipeline", detail: "Reports are stored. Triage, human review, repeat-offender handling and appeals still need to be built."),
        .init(title: "Abuse and rate limiting", detail: "Limits on requests, messages and plan creation; spam and fake-account detection."),
        .init(title: "Data protection", detail: "Encrypted storage, minimal retention and no location history. Apple token revocation on account deletion needs an Edge Function."),
    ]
}
