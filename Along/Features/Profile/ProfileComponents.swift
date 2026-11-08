import SwiftUI

// MARK: - Social icons (drawn, so no brand assets are bundled)

/// Recognisable Instagram / X marks drawn as shapes. They are simple stand-ins, not the official logos.
struct SocialIcon: View {
    let network: SocialNetwork
    var size: CGFloat = 22

    var body: some View {
        switch network {
        case .instagram:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(lineWidth: size * 0.1)
                Circle().stroke(lineWidth: size * 0.1).frame(width: size * 0.46, height: size * 0.46)
                Circle().frame(width: size * 0.1, height: size * 0.1).offset(x: size * 0.22, y: -size * 0.22)
            }
            .frame(width: size, height: size)
        case .x:
            ZStack {
                Capsule().frame(width: size * 0.12, height: size * 1.0).rotationEffect(.degrees(-38))
                Capsule().frame(width: size * 0.12, height: size * 0.7).rotationEffect(.degrees(38))
            }
            .frame(width: size, height: size)
        }
    }
}

/// Instagram and X icons that open the person's public profile. Only shown for validated usernames.
struct SocialLinksView: View {
    let user: User
    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = SocialNetwork.allCases.compactMap { n -> (SocialNetwork, URL, String)? in
            guard let h = user.handle(for: n), let url = n.profileURL(for: h) else { return nil }
            return (n, url, h)
        }
        if !links.isEmpty {
            HStack(spacing: AlongSpacing.sm) {
                ForEach(links, id: \.0) { network, url, handle in
                    Button { Haptics.light(); openURL(url) } label: {
                        SocialIcon(network: network, size: 18)
                            .foregroundStyle(AlongColor.navy)
                            .frame(width: 44, height: 44)
                            .background(AlongColor.surface, in: Circle())
                    }
                    .buttonStyle(AlongPressStyle(scale: 0.94))
                    .accessibilityLabel("\(network.title): @\(handle)")
                    .accessibilityHint("Opens their public profile")
                }
            }
        }
    }
}

// MARK: - Pills

struct HobbyPills: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 8) { ForEach(items, id: \.self) { AlongChip(title: $0) } }
    }
}

/// A titled block used on profiles. Hidden when there is nothing to show.
struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            AlongSectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Interests

/// Categorised, searchable hobby picker with custom tags. Edits `selection` in place.
struct InterestsSelectionView: View {
    @Binding var selection: [String]
    @State private var query = ""
    @State private var custom = ""

    private var matches: [HobbyCatalog.Category] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return HobbyCatalog.categories }
        return HobbyCatalog.categories.compactMap { c in
            let hits = c.hobbies.filter { $0.localizedCaseInsensitiveContains(q) }
            return hits.isEmpty ? nil : .init(name: c.name, hobbies: hits)
        }
    }

    private var customSelected: [String] { selection.filter { !HobbyCatalog.all.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            HStack(spacing: AlongSpacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(AlongColor.textSecondary)
                TextField("Search interests", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AlongColor.textSecondary) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, AlongSpacing.sm + 2)
            .frame(minHeight: AlongSize.minTouch)
            .background(AlongColor.white, in: Capsule())
            .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))

            ForEach(matches) { category in
                VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                    AlongSectionLabel(category.name)
                    FlowLayout(spacing: 8) {
                        ForEach(category.hobbies, id: \.self) { hobby in
                            Button { toggle(hobby) } label: {
                                AlongChip(title: hobby, isSelected: selection.contains(hobby)).frame(minHeight: AlongSize.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection.contains(hobby) ? .isSelected : [])
                        }
                    }
                }
            }
            if matches.isEmpty {
                Text("No match. Add it as your own interest below.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }

            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                AlongSectionLabel("Your own")
                if !customSelected.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(customSelected, id: \.self) { hobby in
                            Button { toggle(hobby) } label: {
                                HStack(spacing: 4) {
                                    Text(hobby)
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                }
                                .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.white)
                                .padding(.horizontal, AlongSpacing.sm + 2).padding(.vertical, 7)
                                .background(AlongColor.navy, in: Capsule())
                                .frame(minHeight: AlongSize.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(hobby)")
                        }
                    }
                }
                HStack(spacing: AlongSpacing.xs) {
                    TextField("Add an interest", text: $custom)
                        .submitLabel(.done).onSubmit(addCustom)
                        .padding(.horizontal, AlongSpacing.sm + 2)
                        .frame(minHeight: AlongSize.minTouch)
                        .background(AlongColor.white, in: Capsule())
                        .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
                    Button("Add", action: addCustom)
                        .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                        .frame(minHeight: AlongSize.minTouch)
                        .disabled(HobbyCatalog.cleaned(custom) == nil)
                }
            }
            if selection.count >= HobbyCatalog.maxSelected {
                Text("That's the maximum of \(HobbyCatalog.maxSelected).").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
        }
    }

    private func toggle(_ hobby: String) {
        Haptics.selection()
        if let i = selection.firstIndex(of: hobby) { selection.remove(at: i) }
        else if selection.count < HobbyCatalog.maxSelected { selection.append(hobby) }
    }

    private func addCustom() {
        guard let hobby = HobbyCatalog.cleaned(custom) else { return }
        custom = ""
        if let existing = selection.first(where: { $0.caseInsensitiveCompare(hobby) == .orderedSame }) { _ = existing; return }
        if selection.count < HobbyCatalog.maxSelected { Haptics.selection(); selection.append(hobby) }
    }
}

// MARK: - Walking preferences

/// Pace, duration, neighbourhoods and favourite mode. Edits the bindings in place.
struct WalkingPreferencesView: View {
    @Binding var pace: PacePreference?
    @Binding var duration: Int?
    @Binding var neighborhoods: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            group("Preferred walking pace") {
                ForEach(PacePreference.allCases) { p in
                    chip(p.rawValue, selected: pace == p) { pace = pace == p ? nil : p }
                }
            }
            group("Preferred walk duration") {
                ForEach(WalkDuration.options, id: \.self) { m in
                    chip(WalkDuration.label(m), selected: duration == m) { duration = duration == m ? nil : m }
                }
            }
            group("Favorite neighborhoods") {
                ForEach(Neighborhoods.options, id: \.self) { n in
                    chip(n, selected: neighborhoods.contains(n)) {
                        if let i = neighborhoods.firstIndex(of: n) { neighborhoods.remove(at: i) }
                        else if neighborhoods.count < Neighborhoods.maxSelected { neighborhoods.append(n) }
                    }
                }
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            AlongSectionLabel(title)
            FlowLayout(spacing: 8) { content() }
        }
    }

    private func chip(_ title: String, selected: Bool, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            AlongChip(title: title, isSelected: selected, symbol: symbol).frame(minHeight: AlongSize.minTouch)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Things I love talking about": topic chips plus up to three short custom answers.
struct ConversationInterestsView: View {
    @Binding var topics: [ConversationTopic]
    @Binding var custom: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            FlowLayout(spacing: 8) {
                ForEach(ConversationTopic.allCases) { t in
                    Button {
                        Haptics.selection()
                        if let i = topics.firstIndex(of: t) { topics.remove(at: i) } else if topics.count < 6 { topics.append(t) }
                    } label: {
                        AlongChip(title: t.rawValue, isSelected: topics.contains(t)).frame(minHeight: AlongSize.minTouch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(topics.contains(t) ? .isSelected : [])
                }
            }
            if !custom.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(custom, id: \.self) { c in
                        Button { custom.removeAll { $0 == c } } label: {
                            HStack(spacing: 4) { Text(c); Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.white)
                                .padding(.horizontal, AlongSpacing.sm + 2).padding(.vertical, 7)
                                .background(AlongColor.navy, in: Capsule())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Remove \(c)")
                    }
                }
            }
            if custom.count < 3 {
                AlongTextField(label: "Or in your own words", text: $draft, prompt: "e.g. Why cities feel the way they do", limit: 40)
                    .onSubmit(add)
                Button("Add", action: add)
                    .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                    .frame(minHeight: AlongSize.minTouch)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, custom.count < 3, !custom.contains(t) else { return }
        custom.append(String(t.prefix(40)))
        draft = ""
    }
}

// MARK: - Social account fields

/// An optional username field that accepts "@name", "name" or a pasted profile link and keeps only the clean username.
struct SocialUsernameField: View {
    let network: SocialNetwork
    @Binding var username: String?
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isInvalid: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty && network.username(from: text) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AlongSpacing.sm) {
                SocialIcon(network: network, size: 20).foregroundStyle(AlongColor.navy).frame(width: 24)
                TextField("\(network.title) username", text: $text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($focused)
                    .onChange(of: text) { _, new in username = network.username(from: new) }
            }
            .padding(.horizontal, AlongSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AlongSize.button, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous)
                .stroke(isInvalid ? AlongColor.destructive : AlongColor.border, lineWidth: 1))
            if isInvalid {
                Text("That doesn't look like a \(network.title) username.").font(AlongFont.caption).foregroundStyle(AlongColor.destructive)
            }
        }
        .onAppear { text = username ?? "" }
    }
}
