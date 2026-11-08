import SwiftUI

/// Everything that used to sit at the bottom of the Profile screen, now behind the gear: edit profile, privacy, about,
/// log out and delete account. Same rows, same actions.
struct SettingsHomeView: View {
    let store: AppStore
    @Environment(AppSession.self) private var session
    @State private var showEdit = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                Text("Settings").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(AlongColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    Button { showEdit = true } label: { SettingsRow(symbol: "pencil", title: "Edit Profile") }.buttonStyle(.plain)
                    AlongDivider()
                    link(.history, "figure.walk.motion", "Your Walks")
                    AlongDivider()
                    link(.visibility, "eye", "Profile Visibility")
                    AlongDivider()
                    link(.location, "location", "Location Privacy")
                    AlongDivider()
                    link(.notifications, "bell", "Notifications")
                    AlongDivider()
                    link(.blocked, "nosign", "Blocked Users")
                    AlongDivider()
                    link(.about, "info.circle", "About Along")
                    if session.isLive {
                        AlongDivider()
                        Button { confirmSignOut = true } label: { SettingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Log Out", showsChevron: false) }
                            .buttonStyle(.plain)
                        AlongDivider()
                        Button { confirmDelete = true } label: { SettingsRow(symbol: "trash", title: "Delete Account", showsChevron: false, tint: AlongColor.destructive) }
                            .buttonStyle(.plain)
                    }
                }
                .alongCard()
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.bottom, AlongSpacing.xl)
        }
        .alongScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Log out of Along?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await session.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your profile, plans, requests and messages are permanently deleted. This can't be undone.") }
        .sheet(isPresented: $showEdit) {
            EditProfileView(store: store)
                .alongToasts()
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
    }

    private func link(_ dest: SettingsDestination, _ symbol: String, _ title: String) -> some View {
        NavigationLink(value: dest) { SettingsRow(symbol: symbol, title: title) }.buttonStyle(.plain)
    }
}
