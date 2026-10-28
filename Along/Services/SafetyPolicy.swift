import Foundation

/// A single place that documents how safety is handled in Phase 1.
///
/// Phase 1 *simulates* these protections locally so the experience can be designed and tested.
/// A simulation is a UI affordance, not a guarantee: before Along ships, every item under
/// `requiredBeforeProduction` has to be enforced by the backend.
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
        .init(title: "Server-side authorisation", detail: "Row Level Security so users can only read or change what they own or have been granted."),
        .init(title: "Server-side redaction", detail: "Exact locations and meeting notes must never be sent to unaccepted users in the first place."),
        .init(title: "Verified age and identity", detail: "Age assurance and account verification that can't be bypassed on the device."),
        .init(title: "Moderation pipeline", detail: "Report triage, human review, repeat-offender handling and appeals."),
        .init(title: "Enforced blocking", detail: "Blocks applied in every query, push notification and real-time channel."),
        .init(title: "Abuse and rate limiting", detail: "Limits on requests, messages and plan creation; spam and fake-account detection."),
        .init(title: "Data protection", detail: "Encrypted storage, minimal retention, no location history, and account deletion."),
    ]
}
