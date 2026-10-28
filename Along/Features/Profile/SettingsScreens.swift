import SwiftUI
import CoreLocation

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) { content() }
                .padding(AlongSpacing.gutter)
        }
        .alongScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                if let detail { Text(detail).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary) }
            }
        }
        .tint(AlongColor.navy)
        .padding(.horizontal, AlongSpacing.md)
        .frame(minHeight: AlongSize.minTouch + 12)
    }
}

// MARK: - Profile visibility

struct ProfileVisibilityView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsPage(title: "Profile Visibility") {
            Text("Choose who can see your name, bio and interests. This is separate from location — see Location Privacy.")
                .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(ProfileVisibility.allCases.enumerated()), id: \.element) { i, option in
                    if i > 0 { AlongDivider() }
                    Button {
                        Haptics.selection()
                        Task { await store.updateSettings { $0.profileVisibility = option } }
                    } label: {
                        HStack {
                            Text(option.rawValue).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                            Spacer()
                            if store.settings.profileVisibility == option {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(AlongColor.navy)
                            }
                        }
                        .padding(.horizontal, AlongSpacing.md)
                        .frame(minHeight: AlongSize.minTouch + 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.settings.profileVisibility == option ? .isSelected : [])
                }
            }
            .alongCard()
        }
    }
}

// MARK: - Location privacy

struct LocationPrivacyView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location

    var body: some View {
        SettingsPage(title: "Location Privacy") {
            VStack(spacing: 0) {
                ToggleRow(title: "Centre the map on me", detail: "Uses your approximate location, only when you tap the locate button.",
                          isOn: Binding(get: { store.settings.useLocationToCenterMap },
                                        set: { v in Task { await store.updateSettings { $0.useLocationToCenterMap = v } } }))
                AlongDivider()
                HStack {
                    Text("System permission").font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                    Spacer()
                    Text(permissionLabel).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                }
                .padding(.horizontal, AlongSpacing.md)
                .frame(minHeight: AlongSize.minTouch + 12)
                if location.isDenied {
                    AlongDivider()
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.navy)
                    .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch + 8)
                }
            }
            .alongCard()

            VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                AlongSectionLabel("How Along treats location")
                principle("Your live location is never shown to anyone.")
                principle("Public plans show approximate areas, never exact spots.")
                principle("Exact meeting details go only to accepted guests.")
                principle("Along keeps no history of where you've been.")
            }
        }
    }

    private var permissionLabel: String {
        switch location.status {
        case .notDetermined: "Not asked yet"
        case .denied, .restricted: "Off"
        default: "While using the app"
        }
    }

    private func principle(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AlongSpacing.sm) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AlongColor.navy).padding(.top, 4)
            Text(text).font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary)
        }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsPage(title: "Notifications") {
            VStack(spacing: 0) {
                ToggleRow(title: "Join requests", isOn: binding(\.notifyRequests))
                AlongDivider()
                ToggleRow(title: "Messages", isOn: binding(\.notifyMessages))
                AlongDivider()
                ToggleRow(title: "Plan reminders", isOn: binding(\.notifyReminders))
            }
            .alongCard()
            Text("Push notifications arrive with the backend. These preferences are saved locally for now.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
    }

    private func binding(_ key: WritableKeyPath<UserSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: key] }, set: { v in Task { await store.updateSettings { $0[keyPath: key] = v } } })
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsPage(title: "Blocked Users") {
            if store.blockedUsers.isEmpty {
                AlongEmptyState(title: "No one blocked.", message: "People you block won't see your plans or be able to request to join.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.blockedUsers.enumerated()), id: \.element.id) { i, user in
                        if i > 0 { AlongDivider() }
                        HStack(spacing: AlongSpacing.sm) {
                            AlongProfileAvatar(user: user, size: 40)
                            Text(user.firstName).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                            Spacer()
                            AlongSmallButton(title: "Unblock") { Task { await store.unblock(user.id) } }
                        }
                        .padding(.horizontal, AlongSpacing.md)
                        .padding(.vertical, AlongSpacing.xs)
                    }
                }
                .alongCard()
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        SettingsPage(title: "About Along") {
            VStack(spacing: AlongSpacing.sm) {
                AlongLogo(variant: .navy, width: 150)
                Text("Good company, wherever you're headed.")
                    .font(.system(.title3, design: .serif)).foregroundStyle(AlongColor.textPrimary).multilineTextAlignment(.center)
                Text("Version 0.1 · Phase 1 prototype · Manhattan").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AlongSpacing.md)

            safetyGroup("Simulated in this prototype", "iphone", SafetyPolicy.simulatedInPrototype,
                        footer: "These behave correctly on this device, but a modified app could bypass any of them.")
            safetyGroup("Required on the server before launch", "lock.shield", SafetyPolicy.requiredBeforeProduction,
                        footer: "Enforced by the backend, never by the app alone.")

            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                AlongSectionLabel("Demo controls")
                VStack(spacing: 0) {
                    ToggleRow(title: "Hosts respond automatically", detail: "So you can try both sides of a request on your own.",
                              isOn: Binding(get: { store.settings.demoHostsRespond },
                                            set: { v in Task { await store.updateSettings { $0.demoHostsRespond = v } } }))
                    AlongDivider()
                    Button { confirmReset = true } label: {
                        Text("Reset demo data").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.destructive)
                            .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch + 12)
                    }
                }
                .alongCard()
            }
        }
        .confirmationDialog("Reset demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await store.resetDemo() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Plans, requests and messages return to how they started.") }
    }

    private func safetyGroup(_ title: String, _ symbol: String, _ items: [SafetyPolicy.Item], footer: String) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Label(title, systemImage: symbol).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                        Text(item.detail).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                }
            }
            .padding(AlongSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .alongCard()
            Text(footer).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
    }
}
