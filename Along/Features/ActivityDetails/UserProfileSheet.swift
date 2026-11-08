import SwiftUI

/// Another person's profile. Report and Block are always visible, never buried.
struct UserProfileSheet: View {
    let userID: ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var stats: WalkStats?

    var body: some View {
        NavigationStack {
            Group {
                if let user = store.user(userID) {
                    ScrollView {
                        VStack(spacing: AlongSpacing.lg) {
                            DetailedProfileView(user: user, stats: stats, isMine: user.id == store.me.id)
                                .padding(.top, AlongSpacing.md)

                            if user.id != store.me.id {
                                AlongDivider()
                                HStack(spacing: AlongSpacing.sm) {
                                    AlongButton(title: "Report", symbol: "flag", style: .secondary) { showReport = true }
                                    AlongButton(title: "Block", symbol: "nosign", style: .destructive) { confirmBlock = true }
                                }
                            }
                        }
                        .padding(.horizontal, AlongSpacing.gutter)
                        .padding(.bottom, AlongSpacing.xl)
                    }
                } else {
                    AlongEmptyState(title: "Profile unavailable.", message: "This person isn't visible to you.")
                }
            }
            .alongScreenBackground()
            .task { stats = try? await store.walks.publicStats(userID: userID) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(AlongColor.navy) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .reportDialog(isPresented: $showReport) { reason in Task { await store.report(.user(userID), reason: reason) } }
            .blockDialog(name: store.user(userID)?.firstName ?? "this person", isPresented: $confirmBlock) {
                Task { await store.block(userID); dismiss() }
            }
        }
        .alongToasts()
    }
}
