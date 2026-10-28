import SwiftUI

/// Another person's profile. Report and Block are always visible, never buried.
struct UserProfileSheet: View {
    let userID: ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false
    @State private var confirmBlock = false

    var body: some View {
        NavigationStack {
            Group {
                if let user = store.user(userID) {
                    ScrollView {
                        VStack(spacing: AlongSpacing.lg) {
                            VStack(spacing: AlongSpacing.sm) {
                                AlongProfileAvatar(user: user, size: 104)
                                Text(user.firstName).font(AlongFont.screenTitle).foregroundStyle(AlongColor.textPrimary)
                                Text(user.neighborhood).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                            }
                            .padding(.top, AlongSpacing.md)

                            Text(user.bio)
                                .font(AlongFont.body).foregroundStyle(AlongColor.textPrimary).multilineTextAlignment(.center)

                            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                                AlongSectionLabel("Interests")
                                FlowLayout(spacing: 8) { ForEach(user.interests) { AlongChip(title: $0.rawValue) } }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                                AlongSectionLabel("Along for")
                                FlowLayout(spacing: 8) {
                                    ForEach(AlongPurpose.allCases.filter { user.alongFor.contains($0) }) { AlongChip(title: $0.rawValue) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

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
