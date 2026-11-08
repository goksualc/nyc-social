import SwiftUI

/// Presents the whole shared-walk journey for one plan: ready → live map → completion. The server's status picks the screen.
struct LiveWalkFlowView: View {
    let activityID: ID
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: LiveWalkViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm { screen(vm) } else { ProgressView() }
            }
            .alongScreenBackground()
        }
        .tint(AlongColor.navy)
        .task {
            let model = vm ?? LiveWalkViewModel(store: store, activityID: activityID, location: location)
            vm = model
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await vm?.refresh() } }       // catch up after the app was in the background
        }
        .interactiveDismissDisabled(vm?.status?.isLive ?? false)       // a live walk is ended on purpose, never swiped away
        .onDisappear { Task { await vm?.stop(endTracking: !(vm?.status?.isLive ?? false)) } }
    }

    @ViewBuilder private func screen(_ vm: LiveWalkViewModel) -> some View {
        if let status = vm.status {
            switch status {
            case .awaitingParticipants, .readyToStart:
                WalkReadyView(vm: vm) { dismiss() }
            case .active, .awaitingCompletion:
                LiveWalkMapView(vm: vm) { dismiss() }
            case .completed:
                WalkCompletionView(vm: vm) { dismiss() }
            case .cancelled, .endedEarly, .expired:
                WalkEndedView(status: status, partnerName: vm.partner?.firstName) { dismiss() }
            }
        } else if let message = vm.loadFailed {
            VStack(spacing: AlongSpacing.md) {
                AlongEmptyState(title: "Couldn't open this walk.", message: message, actionTitle: "Try again") { Task { await vm.refresh() } }
                AlongButton(title: "Close", style: .ghost) { dismiss() }.padding(.horizontal, AlongSpacing.gutter)
            }
        } else {
            ProgressView().controlSize(.large)
        }
    }
}

/// Shown when a session finished without both people confirming: ended early, cancelled, or timed out.
struct WalkEndedView: View {
    let status: WalkSessionStatus
    let partnerName: String?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: AlongSpacing.lg) {
            Spacer()
            Image(systemName: status == .endedEarly ? "figure.walk.departure" : "clock.badge.xmark")
                .font(.system(size: 44)).foregroundStyle(AlongColor.navy)
            Text(title).font(AlongFont.walkScreenHeading).foregroundStyle(AlongColor.textPrimary).multilineTextAlignment(.center)
            Text(message).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary).multilineTextAlignment(.center)
            Spacer()
            AlongButton(title: "Back to Explore", action: onClose)
        }
        .padding(AlongSpacing.gutter + 4)
    }

    private var title: String {
        switch status {
        case .endedEarly: "This walk ended early."
        case .cancelled: "This walk was cancelled."
        default: "This walk timed out."
        }
    }
    private var message: String {
        switch status {
        case .endedEarly: "It wasn't counted as a completed walk. Location sharing has stopped."
        case .cancelled: "Location sharing never started."
        default: "We didn't hear back in time, so it wasn't counted. Location sharing has stopped."
        }
    }
}
