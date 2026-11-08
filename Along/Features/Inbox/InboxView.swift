import SwiftUI

struct InboxView: View {
    @State private var vm: InboxViewModel
    @State private var path: [AlongRoute] = LaunchOptions.current.conversation.map { [.conversation($0)] } ?? []
    @Environment(AppStore.self) private var store

    init(store: AppStore) { _vm = State(initialValue: InboxViewModel(store: store)) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    AlongScreenHeader(title: "Chat")
                    ChatSearchField(text: $vm.query)
                    AlongPillRow(items: InboxViewModel.Filter.allCases, title: \.rawValue, badge: { badge(for: $0) }, selection: $vm.filter)

                    switch vm.filter {
                    case .requests: requests
                    default: conversationList
                    }
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.top, AlongSpacing.xs)
                .padding(.bottom, AlongSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .alongDestinations()
            .sheet(item: $vm.profile) { item in
                UserProfileSheet(userID: item.id)
                    .presentationDetents([.large])
                    .presentationCornerRadius(AlongRadius.sheet)
                    .presentationBackground(AlongColor.offWhite)
            }
        }
    }

    private func badge(for filter: InboxViewModel.Filter) -> Int {
        switch filter { case .requests: vm.pendingCount; case .unread: vm.unreadCount; default: 0 }
    }

    // MARK: Conversations

    @ViewBuilder private var conversationList: some View {
        let list = vm.visibleConversations.filter { store.otherParticipant(in: $0) != nil }
        if list.isEmpty && vm.isSearching {
            AlongEmptyState(title: "No conversations found.", message: "Nothing matches “\(vm.query.trimmingCharacters(in: .whitespacesAndNewlines))”. Try a name, a message or a walk title.")
                .padding(.top, AlongSpacing.xl)
        } else if list.isEmpty && (vm.filter != .all || vm.requests.isEmpty) {
            AlongEmptyState(title: vm.filter == .unread ? "You're all caught up." : "No messages yet.",
                            message: vm.filter == .unread ? "New messages will show up here." : "When a walking buddy is accepted, your conversation starts here.")
                .padding(.top, AlongSpacing.xl)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(list) { c in
                    if let other = store.otherParticipant(in: c) { conversationRow(c, other); AlongDivider() }
                }
            }
            if vm.filter == .all, !vm.requests.isEmpty, !vm.isSearching { requestsCard.padding(.top, AlongSpacing.xs) }
        }
    }

    private func conversationRow(_ c: Conversation, _ other: User) -> some View {
        let last = store.lastMessage(in: c)
        let open = store.isOpen(c)
        let unread = vm.isUnread(c)
        return VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            NavigationLink(value: AlongRoute.conversation(c.id)) {
                HStack(alignment: .top, spacing: AlongSpacing.sm + 2) {
                    AlongProfileAvatar(user: other, size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(other.firstName).font(.system(size: 18, weight: .bold)).foregroundStyle(AlongColor.textPrimary)
                            Spacer()
                            if let last { Text(ActivityTime.stamp(last.sentAt, now: store.now)).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary) }
                        }
                        HStack(spacing: 8) {
                            Text(open ? (last?.text ?? "Say hello") : "Conversation closed")
                                .font(.system(size: 15, weight: unread ? .semibold : .regular))
                                .foregroundStyle(unread ? AlongColor.textPrimary : AlongColor.textTertiary).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if unread { Circle().fill(AlongColor.navy).frame(width: 10, height: 10).accessibilityLabel("Unread") }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // A small card for the walk this chat is about, while it's still ahead of you.
            if let walk = vm.upcomingWalk(for: c) {
                NavigationLink(value: AlongRoute.activity(walk.id)) {
                    HStack(spacing: AlongSpacing.sm) {
                        Image(systemName: "figure.walk").font(.system(size: 17)).foregroundStyle(AlongColor.navy)
                            .frame(width: 26, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(walk.title).font(AlongRoboto.bold(15, relativeTo: .subheadline)).foregroundStyle(AlongColor.textPrimary).lineLimit(2)
                            Text("\(ActivityTime.summary(walk, now: store.now, separator: " · ")) · \(walk.walk.from.area)")
                                .font(.system(size: 13)).foregroundStyle(AlongColor.textTertiary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
                    }
                    .padding(.horizontal, AlongSpacing.sm + 2).padding(.vertical, AlongSpacing.xs + 2)
                    .background(AlongColor.navy.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 54 + AlongSpacing.sm + 2)
            }
        }
        .padding(.vertical, AlongSpacing.sm)
        .opacity(open ? 1 : 0.6)
    }

    private var requestsCard: some View {
        let pending = vm.pendingCount
        return Button { alongWithAnimation { vm.filter = .requests } } label: {
            HStack(spacing: AlongSpacing.sm + 2) {
                Image(systemName: "person.2").font(.system(size: 22)).foregroundStyle(AlongColor.navy).frame(width: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Walk Requests").font(.system(size: 18, weight: .bold)).foregroundStyle(AlongColor.textPrimary)
                    Text(pending == 0 ? "No new requests" : "\(pending) \(pending == 1 ? "person wants" : "people want") to join your walks")
                        .font(.system(size: 14)).foregroundStyle(AlongColor.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
            }
            .padding(AlongSpacing.md)
            .background(AlongColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(AlongPressStyle(scale: 0.985))
        .accessibilityElement(children: .combine)
    }

    // MARK: Requests

    @ViewBuilder private var requests: some View {
        if vm.requests.isEmpty && vm.isSearching {
            AlongEmptyState(title: "No requests found.", message: "Nothing matches your search.").padding(.top, AlongSpacing.xl)
        } else if vm.requests.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: AlongSpacing.sm) {
                ForEach(vm.requests) { request in requestCard(request) }
            }
            .alongAnimation(value: vm.requests.map(\.status))
        }
    }

    private func requestCard(_ r: JoinRequest) -> some View {
        let user = vm.user(r.requesterID)
        let activity = vm.activity(r.activityID)
        return VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            NavigationLink(value: AlongRoute.activity(r.activityID)) {
                HStack(alignment: .top, spacing: AlongSpacing.sm) {
                    if let user { AlongProfileAvatar(user: user, size: 44) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.headline(for: r)).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary).multilineTextAlignment(.leading)
                        if let activity {
                            Text(ActivityTime.summary(activity, now: store.now)).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                            Text(activity.title).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            switch r.status {
            case .pending:
                HStack(spacing: AlongSpacing.xs) {
                    AlongSmallButton(title: "View Profile") { vm.profile = IDItem(id: r.requesterID) }
                    Spacer(minLength: 0)
                    if vm.isFull(r) {
                        Text("Plan is full").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                    } else {
                        AlongSmallButton(title: "Accept", filled: true) { Task { await vm.respond(r, accept: true) } }
                    }
                    AlongSmallButton(title: "Decline") { Task { await vm.respond(r, accept: false) } }
                }
            case .accepted:
                HStack {
                    Label("Accepted", systemImage: "checkmark").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                    Spacer()
                    if let chat = vm.chat(for: r) {
                        NavigationLink(value: AlongRoute.conversation(chat.id)) {
                            Text("Message").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                                .frame(minHeight: AlongSize.minTouch)
                        }
                    }
                }
            default:
                Text("Declined").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textTertiary)
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
        .opacity(r.status == .pending ? 1 : 0.8)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        AlongEmptyState(title: "No requests right now.", message: "When someone asks to join one of your walks, you can accept or decline here.")
            .padding(.top, AlongSpacing.xl)
    }
}

/// "Search conversations…" — a quiet rounded field in the Along palette.
private struct ChatSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: AlongSpacing.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular)).foregroundStyle(AlongColor.textSecondary)
                .accessibilityHidden(true)
            TextField("Search conversations...", text: $text)
                .font(AlongFont.body)
                .foregroundStyle(AlongColor.navy)
                .tint(AlongColor.navy)
                .focused($focused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { focused = false }
            if !text.isEmpty {
                Button { text = ""; Haptics.selection() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(AlongColor.textSecondary)
                        .frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, AlongSpacing.md)
        .padding(.trailing, text.isEmpty ? AlongSpacing.md : 0)
        .frame(minHeight: AlongSize.minTouch + 2)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AlongColor.border.opacity(0.7), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}
