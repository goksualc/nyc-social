import SwiftUI
import PhotosUI

struct ProfileView: View {
    @State private var vm: ProfileViewModel
    @Environment(AppSession.self) private var session

    init(store: AppStore) { _vm = State(initialValue: ProfileViewModel(store: store)) }

    private var me: User { vm.me }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    AlongScreenHeader { NavigationLink(value: SettingsDestination.home) { settingsIcon } .buttonStyle(AlongPressStyle(scale: 0.94)) }
                    identity
                    if !me.hobbies.isEmpty { interests }
                    preferences
                    stats
                    recent
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.top, AlongSpacing.xs)
                .padding(.bottom, AlongSpacing.xl)
            }
            .alongScreenBackground()
            .task { await vm.loadStats() }
            .refreshable { await vm.loadStats() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .home: SettingsHomeView(store: vm.store)
                case .visibility: ProfileVisibilityView()
                case .location: LocationPrivacyView()
                case .notifications: NotificationsView()
                case .blocked: BlockedUsersView()
                case .about: AboutView()
                case .history: WalkHistoryView(store: vm.store)
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

    private var settingsIcon: some View {
        Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(AlongColor.navy)
            .frame(width: 44, height: 44).background(AlongColor.white, in: Circle())
            .overlay(Circle().stroke(AlongColor.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            .accessibilityLabel("Settings")
    }

    // MARK: Identity

    private var identity: some View {
        HStack(alignment: .top, spacing: AlongSpacing.md) {
            AlongProfileAvatar(user: me, size: 104)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(me.firstName).font(AlongFont.profileName).foregroundStyle(AlongColor.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let age = me.age { Text("\(age)").font(.title3).foregroundStyle(AlongColor.textTertiary) }
                }
                Label(me.neighborhood, systemImage: "mappin.and.ellipse").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                if !me.bio.isEmpty {
                    Text(me.bio).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: AlongSpacing.xs) {
                    SocialLinksView(user: me)
                    Button { Haptics.light(); vm.isEditing = true } label: {
                        Label("Edit", systemImage: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(AlongColor.navy)
                            .padding(.horizontal, 14).frame(height: 36).background(AlongColor.white, in: Capsule())
                            .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
                    }
                    .buttonStyle(AlongPressStyle(scale: 0.96))
                    .accessibilityLabel("Edit profile")
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: Interests

    private var interests: some View {
        FlowLayout(spacing: 10) {
            ForEach(me.hobbies, id: \.self) { hobby in
                HStack(spacing: 6) {
                    if let symbol = HobbyIcon.symbol(for: hobby) { Image(systemName: symbol).font(.system(size: 13)) }
                    Text(hobby).font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(AlongColor.navy)
                .padding(.horizontal, 14).frame(height: 38)
                .background(AlongColor.surface, in: Capsule())
            }
        }
    }

    // MARK: Walking preferences

    private var preferences: some View {
        let topics = me.discussionTopics.map(\.rawValue) + me.conversationCustom
        let rows: [(String, String, String)] = [
            me.pacePreference.map { ("speedometer", "Pace", "\($0.rawValue) pace") },
            me.preferredDuration.map { ("clock", "Duration", WalkDuration.label($0)) },
            me.favoriteNeighborhoods.isEmpty ? nil : ("mappin.and.ellipse", "Favorite neighborhoods", me.favoriteNeighborhoods.joined(separator: ", ")),
            topics.isEmpty ? nil : ("bubble.left.and.bubble.right", "Let's talk about", topics.joined(separator: ", ")),
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: AlongSpacing.sm + 2) {
            HStack {
                Text("Walking Preferences").font(.system(size: 20, weight: .bold)).foregroundStyle(AlongColor.textPrimary)
                Spacer()
                Button { vm.isEditing = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 16)).foregroundStyle(AlongColor.textTertiary)
                        .frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .accessibilityLabel("Edit walking preferences")
            }
            if rows.isEmpty {
                Text("Add your pace, favorite neighborhoods and what you like to talk about, so people know what to expect.")
                    .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                AlongButton(title: "Add preferences", style: .secondary) { vm.isEditing = true }
            } else {
                ForEach(rows, id: \.1) { symbol, label, value in
                    HStack(alignment: .top, spacing: AlongSpacing.sm) {
                        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(AlongColor.navy).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(AlongColor.textPrimary)
                            Text(value).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    // MARK: Statistics (from completed walks; never invented)

    private var stats: some View {
        let s = vm.stats ?? .zero
        let miles = Double(s.distanceMeters) / 1609.344
        let hours = Double(s.durationSeconds) / 3600
        return HStack(spacing: AlongSpacing.sm) {
            StatTile(symbol: "figure.2.walk", value: "\(s.walks)", label: s.walks == 1 ? "walk" : "walks", tint: AlongColor.navy.opacity(0.08))
            StatTile(symbol: "mappin.and.ellipse", value: String(format: "%.1f", miles), label: "miles", tint: Color(hex: 0xF2ECDD))
            StatTile(symbol: "clock", value: hours < 1 ? "\(s.durationSeconds / 60)m" : String(format: "%.0fh", hours.rounded()), label: "walked", tint: AlongColor.surface)
        }
    }

    // MARK: Recent walks

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack {
                Text("Recent Walks").font(AlongFont.sectionHeading).foregroundStyle(AlongColor.textPrimary)
                Spacer()
                NavigationLink(value: SettingsDestination.history) {
                    Text("View All").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary).frame(minHeight: 44)
                }
            }
            if vm.recentWalks.isEmpty {
                Text("Walks you finish together show up here. They're private to you.")
                    .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                    .padding(AlongSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AlongColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AlongSpacing.sm) { ForEach(vm.recentWalks) { recentCard($0) } }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// No exact places or GPS: just the title, date, distance, and the general route the walk was planned along.
    private func recentCard(_ walk: CompletedWalk) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [AlongColor.navy, AlongColor.navy.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "figure.walk").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.white.opacity(0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(14)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(walk.title).font(AlongRoboto.bold(16, relativeTo: .subheadline)).foregroundStyle(.white).lineLimit(2)
                Text("\(walk.startedAt.formatted(.dateTime.month(.abbreviated).day())) · \(DistanceFormat.miles(Double(walk.distanceMeters)))")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(AlongSpacing.sm + 2)
        }
        .frame(width: 190, height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(walk.title), \(walk.startedAt.formatted(date: .abbreviated, time: .omitted)), \(DistanceFormat.miles(Double(walk.distanceMeters)))")
    }
}

/// SF Symbols for the common hobbies (custom ones simply show no icon).
enum HobbyIcon {
    static func symbol(for hobby: String) -> String? {
        switch hobby.lowercased() {
        case "walking", "exploring nyc": "figure.walk"
        case "coffee": "cup.and.saucer"
        case "technology", "ai", "startups", "entrepreneurship": "laptopcomputer"
        case "philosophy", "literature", "history": "book"
        case "baking", "cooking": "fork.knife"
        case "art", "museums", "design", "architecture": "paintpalette"
        case "music", "concerts": "music.note"
        case "movies": "film"
        case "photography": "camera"
        case "traveling": "airplane"
        case "running", "gym", "pilates", "yoga", "hiking", "cycling", "tennis", "kayaking": "figure.run"
        case "fashion": "tshirt"
        case "finance", "crypto": "chart.line.uptrend.xyaxis"
        case "science", "research", "psychology": "atom"
        case "politics", "current events": "newspaper"
        case "deep conversations": "bubble.left.and.bubble.right"
        case "language learning": "character.bubble"
        default: nil
        }
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

    private var isBusyWithPhoto: Bool { isUploading || store.isUpdatingAvatar }

    /// Square 512 px JPEG, compressed (see `AvatarImage`).
    static func avatarJPEG(from data: Data) -> Data? { AvatarImage.jpeg(from: data) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    VStack(spacing: AlongSpacing.xs) {
                        // Always the live profile: a new photo shows here the moment it's saved, even while the rest of the form is being edited.
                        AlongProfileAvatar(user: store.me, size: 88)
                            .overlay { if isBusyWithPhoto { ProgressView().padding(24).background(.thinMaterial, in: Circle()) } }
                        if store.supportsAvatars {
                            HStack(spacing: AlongSpacing.md) {
                                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                                    Text(isBusyWithPhoto ? "Updating…" : (store.me.avatarPath == nil ? "Add photo" : "Change photo"))
                                        .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                                        .frame(minHeight: AlongSize.minTouch)
                                }
                                .disabled(isBusyWithPhoto)
                                if store.me.avatarPath != nil {
                                    Button("Remove") { Task { await store.removeAvatar() } }
                                        .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textTertiary)
                                        .frame(minHeight: AlongSize.minTouch)
                                        .disabled(isBusyWithPhoto)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    AlongTextField(label: "First name", text: $draft.firstName, prompt: "Your first name", limit: 24)
                    AlongTextField(label: "Bio", text: $draft.bio, prompt: "A line or two about you", axis: .vertical, lines: 2...4, limit: 120)

                    AlongTextField(label: "Occupation", text: Binding(get: { draft.occupation ?? "" }, set: { draft.occupation = $0 }), prompt: "Optional", limit: 60)
                    AlongTextField(label: "University", text: Binding(get: { draft.university ?? "" }, set: { draft.university = $0 }), prompt: "Optional", limit: 80)

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Languages")
                        FlowLayout(spacing: 8) {
                            ForEach(Languages.common, id: \.self) { language in
                                Button {
                                    Haptics.selection()
                                    if let i = draft.languages.firstIndex(of: language) { draft.languages.remove(at: i) }
                                    else if draft.languages.count < Languages.maxSelected { draft.languages.append(language) }
                                } label: { AlongChip(title: language, isSelected: draft.languages.contains(language)).frame(minHeight: AlongSize.minTouch) }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Social accounts")
                        SocialUsernameField(network: .instagram, username: $draft.instagram)
                        SocialUsernameField(network: .x, username: $draft.xHandle)
                        Text("Optional. Along only stores the username to link to your public profile. It doesn't verify accounts, and never asks for a password.")
                            .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Interests")
                        InterestsSelectionView(selection: $draft.hobbies)
                    }

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Things I love talking about")
                        ConversationInterestsView(topics: $draft.discussionTopics, custom: $draft.conversationCustom)
                    }

                    WalkingPreferencesView(pace: $draft.pacePreference, duration: $draft.preferredDuration,
                                           neighborhoods: $draft.favoriteNeighborhoods)

                    VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                        AlongSectionLabel("Privacy")
                        if store.me.age != nil {
                            Toggle("Show my age on my profile", isOn: Binding(
                                get: { store.settings.showAge }, set: { on in Task { await store.updateSettings { $0.showAge = on } } }))
                        }
                        Toggle("Show my walk totals on my profile", isOn: Binding(
                            get: { store.settings.showWalkStats }, set: { on in Task { await store.updateSettings { $0.showWalkStats = on } } }))
                        Text("Totals are only counts. Individual walks, routes and places are never public.")
                            .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                    .tint(AlongColor.navy)

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
                        .disabled(draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty || isBusyWithPhoto)
                }
            }
        }
    }
}
