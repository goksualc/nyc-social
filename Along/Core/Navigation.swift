import SwiftUI

/// Destinations that can be pushed from any tab's NavigationStack.
enum AlongRoute: Hashable {
    case activity(ID)
    case conversation(ID)
}

extension View {
    /// Registers the shared push destinations. Apply once at the root of every NavigationStack.
    func alongDestinations() -> some View {
        navigationDestination(for: AlongRoute.self) { route in
            switch route {
            case .activity(let id): ActivityDetailView(activityID: id)
            case .conversation(let id): ConversationView(conversationID: id)
            }
        }
    }
}

/// Identifiable wrapper used to drive `.sheet(item:)` from an ID.
struct IDItem: Identifiable { let id: ID }
