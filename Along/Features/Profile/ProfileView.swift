import SwiftUI
import PhotosUI

struct ProfileView: View {
    @State private var vm: ProfileViewModel
    @Environment(AppSession.self) private var session
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

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
                            if session.isLive {
                                AlongDivider()
                                Button { confirmSignOut = true } label: { SettingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign Out", showsChevron: false) }
                                    .buttonStyle(.plain)
                                AlongDivider()
                                Button { confirmDelete = true } label: { SettingsRow(symbol: "trash", title: "Delete Account", showsChevron: false, tint: AlongColor.destructive) }
                                    .buttonStyle(.plain)
                            }
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
            .confirmationDialog("Sign out of Along?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) { Task { await session.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your profile, plans, requests and messages are permanently deleted. This can't be undone.") }
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
    var showsChevron = true
    var tint: Color = AlongColor.navy
    var body: some View {
        HStack(spacing: AlongSpacing.sm) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(tint).frame(width: 24)
            Text(title).font(AlongFont.body).foregroundStyle(tint == AlongColor.navy ? AlongColor.textPrimary : tint)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
            }
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
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isUploading = false
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore) {
        self.store = store
        _draft = State(initialValue: store.me)
    }

    /// Square-crops to the centre and resizes to 512 px so uploads stay small (well under the 2 MB bucket limit).
    static func avatarJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let target = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * 512 / side, y: -crop.minY * 512 / side,
                                  width: image.size.width * 512 / side, height: image.size.height * 512 / side))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    VStack(spacing: AlongSpacing.xs) {
                        AlongProfileAvatar(user: store.me.avatarPath == draft.avatarPath ? draft : { var u = draft; u.avatarPath = store.me.avatarPath; return u }(), size: 88)
                            .overlay { if isUploading { ProgressView().padding(24).background(.thinMaterial, in: Circle()) } }
                        if store.supportsAvatars {
                            HStack(spacing: AlongSpacing.md) {
                                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                                    Text(store.me.avatarPath == nil ? "Add photo" : "Change photo")
                                        .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                                        .frame(minHeight: AlongSize.minTouch)
                                }
                                if store.me.avatarPath != nil {
                                    Button("Remove") { Task { await store.removeAvatar() } }
                                        .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textTertiary)
                                        .frame(minHeight: AlongSize.minTouch)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
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
                    if store.isDemo {
                        Text("This is a local demo profile. Nothing leaves your device in demo mode.")
                            .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                }
                .padding(AlongSpacing.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .alongScreenBackground()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    isUploading = true
                    defer { isUploading = false; pickedPhoto = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = Self.avatarJPEG(from: data) else {
                        store.showToast("Couldn't read that photo.", symbol: "exclamationmark.circle"); return
                    }
                    _ = await store.setAvatar(jpeg: jpeg)
                }
            }
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
