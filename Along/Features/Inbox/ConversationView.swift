import SwiftUI

struct ConversationView: View {
    let conversationID: ID
    @Environment(AppStore.self) private var store

    var body: some View { ConversationContent(store: store, conversationID: conversationID) }
}

@MainActor @Observable
final class ConversationViewModel {
    let store: AppStore
    let conversationID: ID
    var draft = ""
    var showReport = false
    var confirmBlock = false

    init(store: AppStore, conversationID: ID) {
        self.store = store
        self.conversationID = conversationID
    }

    var conversation: Conversation? { store.conversation(id: conversationID) }
    var other: User? { conversation.flatMap(store.otherParticipant(in:)) }
    var activity: Activity? { conversation.flatMap { store.activity($0.activityID) } }
    var messages: [Message] { conversation.map(store.messages(in:)) ?? [] }
    var isOpen: Bool { conversation.map(store.isOpen) ?? false }
    var canSend: Bool { isOpen && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        guard canSend, let c = conversation else { return }
        let text = draft
        draft = ""
        Haptics.soft()
        await store.send(text, in: c)
    }
}

private struct ConversationContent: View {
    @State private var vm: ConversationViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(store: AppStore, conversationID: ID) {
        _vm = State(initialValue: ConversationViewModel(store: store, conversationID: conversationID))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let a = vm.activity { planBanner(a) }
            messageList
            composer
        }
        .alongScreenBackground()
        .navigationTitle(vm.other?.firstName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Report \(vm.other?.firstName ?? "user")", systemImage: "flag") { vm.showReport = true }
                    Button("Block \(vm.other?.firstName ?? "user")", systemImage: "nosign", role: .destructive) { vm.confirmBlock = true }
                } label: { Image(systemName: "ellipsis").frame(width: AlongSize.minTouch, height: AlongSize.minTouch) }
                .accessibilityLabel("More options")
            }
        }
        .reportDialog(isPresented: $vm.showReport) { reason in
            if let o = vm.other { Task { await vm.store.report(.user(o.id), reason: reason) } }
        }
        .blockDialog(name: vm.other?.firstName ?? "this person", isPresented: $vm.confirmBlock) {
            if let o = vm.other { Task { await vm.store.block(o.id); dismiss() } }
        }
    }

    private func planBanner(_ a: Activity) -> some View {
        NavigationLink(value: AlongRoute.activity(a.id)) {
            HStack(spacing: AlongSpacing.sm) {
                Image(systemName: a.kind.symbol).font(.system(size: 14)).foregroundStyle(AlongColor.navy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.title).font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                    Text(ActivityTime.summary(a, now: vm.store.now)).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
                Spacer()
                Text(a.hasPreciseAccess ? "Meeting details" : "View plan")
                    .font(AlongFont.caption).foregroundStyle(AlongColor.navy)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .frame(minHeight: AlongSize.minTouch + 8)
            .background(AlongColor.white)
            .overlay(alignment: .bottom) { AlongDivider() }
        }
        .buttonStyle(.plain)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    let items = vm.messages
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                        let mine = m.senderID == vm.store.me.id
                        let next = i + 1 < items.count ? items[i + 1] : nil
                        let showStamp = next == nil || next!.senderID != m.senderID || next!.sentAt.timeIntervalSince(m.sentAt) > 600
                        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                            bubble(m, mine: mine)
                            if showStamp {
                                Text(ActivityTime.stamp(m.sentAt, now: vm.store.now))
                                    .font(.system(.caption2)).foregroundStyle(AlongColor.textTertiary)
                                    .padding(.horizontal, 4).padding(.bottom, 6)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                        .id(m.id)
                    }
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.vertical, AlongSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: vm.messages.count) { scrollToEnd(proxy, animated: true) }
            .onChange(of: focused) { if focused { scrollToEnd(proxy, animated: true) } }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = vm.messages.last?.id else { return }
        if animated { alongWithAnimation { proxy.scrollTo(last, anchor: .bottom) } } else { proxy.scrollTo(last, anchor: .bottom) }
    }

    private func bubble(_ m: Message, mine: Bool) -> some View {
        Text(m.text)
            .font(AlongFont.body)
            .foregroundStyle(mine ? AlongColor.white : AlongColor.textPrimary)
            .padding(.horizontal, AlongSpacing.md)
            .padding(.vertical, 10)
            .background(mine ? AlongColor.navy : AlongColor.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if !mine { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AlongColor.border, lineWidth: 1) }
            }
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .accessibilityLabel("\(mine ? "You" : vm.other?.firstName ?? "Them"): \(m.text)")
    }

    @ViewBuilder private var composer: some View {
        if vm.isOpen {
            HStack(alignment: .bottom, spacing: AlongSpacing.xs) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .font(AlongFont.body)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, AlongSpacing.md)
                    .padding(.vertical, 11)
                    .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                Button { Task { await vm.send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
                        .background(AlongColor.navy.opacity(vm.canSend ? 1 : 0.3), in: Circle())
                }
                .disabled(!vm.canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, AlongSpacing.md)
            .padding(.vertical, AlongSpacing.xs)
            .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() })
        } else {
            Text("This conversation is closed.")
                .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() })
        }
    }
}
