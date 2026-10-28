import SwiftUI

struct ProfileView: View {
    @State private var vm: ProfileViewModel

    init(store: AppStore) { _vm = State(initialValue: ProfileViewModel(store: store)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    VStack(spacing: AlongSpacing.sm) {
                        AlongProfileAvatar(user: vm.me, size: 112)
                        Text(vm.me.firstName)
                            .font(AlongFont.screenTitle)
                            .foregroundStyle(AlongColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(vm.me.neighborhood).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                        Text(vm.me.bio)
                            .font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AlongSpacing.md)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, AlongSpacing.lg)

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Interests")
                        FlowLayout(spacing: 8) {
                            ForEach(Interest.allCases) { interest in
                                Button { Task { await vm.toggle(interest) } } label: {
                                    AlongChip(title: interest.rawValue, isSelected: vm.me.interests.contains(interest))
                                        .frame(minHeight: AlongSize.minTouch)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(vm.me.interests.contains(interest) ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Along for")
                        FlowLayout(spacing: 8) {
                            ForEach(AlongPurpose.allCases) { purpose in
                                Button { Task { await vm.toggle(purpose) } } label: {
                                    AlongChip(title: purpose.rawValue, isSelected: vm.me.alongFor.contains(purpose),
                                              symbol: purpose == .walkingBuddies ? "figure.walk" : "laptopcomputer")
                                        .frame(minHeight: AlongSize.minTouch)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(vm.me.alongFor.contains(purpose) ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Settings")
                        VStack(spacing: 0) {
                            Button { vm.isEditing = true } label: { SettingsRow(symbol: "pencil", title: "Edit Profile") }
                                .buttonStyle(.plain)
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
                        }
                        .alongCard()
                    }
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.bottom, AlongSpacing.xl)
            }
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .visibility: ProfileVisibilityView()
                case .location: LocationPrivacyView()
                case .notifications: NotificationsView()
                case .blocked: BlockedUsersView()
                case .about: AboutView()
                }
            }
            .sheet(isPresented: $vm.isEditing) {
                EditProfileView(store: vm.store)
                    .alongToasts()
                    .presentationCornerRadius(AlongRadius.sheet)
                    .presentationBackground(AlongColor.offWhite)
            }
        }
    }

    private func link(_ dest: SettingsDestination, _ symbol: String, _ title: String) -> some View {
        NavigationLink(value: dest) { SettingsRow(symbol: symbol, title: title) }.buttonStyle(.plain)
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    var body: some View {
        HStack(spacing: AlongSpacing.sm) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(AlongColor.navy).frame(width: 24)
            Text(title).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
        }
        .padding(.horizontal, AlongSpacing.md)
        .frame(minHeight: AlongSize.minTouch + 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Edit

struct EditProfileView: View {
    private let store: AppStore
    @State private var draft: User
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore) {
        self.store = store
        _draft = State(initialValue: store.me)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    HStack { Spacer(); AlongProfileAvatar(user: draft, size: 88); Spacer() }
                    AlongTextField(label: "First name", text: $draft.firstName, prompt: "Your first name", limit: 24)
                    AlongTextField(label: "Bio", text: $draft.bio, prompt: "A line or two about you", axis: .vertical, lines: 2...4, limit: 120)

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Interests")
                        FlowLayout(spacing: 8) {
                            ForEach(Interest.allCases) { interest in
                                Button {
                                    Haptics.selection()
                                    if let i = draft.interests.firstIndex(of: interest) { draft.interests.remove(at: i) } else { draft.interests.append(interest) }
                                } label: {
                                    AlongChip(title: interest.rawValue, isSelected: draft.interests.contains(interest)).frame(minHeight: AlongSize.minTouch)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("This is a local demo profile. Nothing leaves your device in Phase 1.")
                        .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
                .padding(AlongSpacing.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .alongScreenBackground()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await store.updateProfile(draft); dismiss() } }
                        .fontWeight(.semibold)
                        .disabled(draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
