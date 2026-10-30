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
                    Text("Inbox")
                        .font(AlongFont.screenTitle)
                        .foregroundStyle(AlongColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, AlongSpacing.sm)

                    AlongSegmentedControl(options: ["Requests", "Messages"], selection: $vm.segment, badges: [vm.pendingCount, 0])

                    if vm.segment == 0 { requests } else { messages }
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.bottom, AlongSpacing.xl)
            }
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

    // MARK: Requests

    @ViewBuilder private var requests: some View {
        if vm.requests.isEmpty {
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

    // MARK: Messages

    @ViewBuilder private var messages: some View {
        if vm.conversations.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(vm.conversations) { c in
                    if let other = store.otherParticipant(in: c) {
                        NavigationLink(value: AlongRoute.conversation(c.id)) { conversationRow(c, other) }
                            .buttonStyle(.plain)
                        AlongDivider()
                    }
                }
            }
        }
    }

    private func conversationRow(_ c: Conversation, _ other: User) -> some View {
        let last = store.lastMessage(in: c)
        let open = store.isOpen(c)
        return HStack(spacing: AlongSpacing.sm) {
            AlongProfileAvatar(user: other, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(other.firstName).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                    Spacer()
                    if let last { Text(ActivityTime.stamp(last.sentAt, now: store.now)).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary) }
                }
                Text(store.activity(c.activityID)?.title ?? "").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                Text(open ? (last?.text ?? "") : "Conversation closed")
                    .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary).lineLimit(1)
            }
        }
        .padding(.vertical, AlongSpacing.sm)
        .frame(minHeight: AlongSize.minTouch)
        .contentShape(Rectangle())
        .opacity(open ? 1 : 0.6)
    }

    private var emptyState: some View {
        AlongEmptyState(title: "Nothing here yet.", message: "Your requests and messages will show up here.")
            .padding(.top, AlongSpacing.xxl)
    }
}
