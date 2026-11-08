import SwiftUI

/// "Your Walks": totals and the completed walks you shared. Private to you.
struct WalkHistoryView: View {
    let store: AppStore
    @State private var walks: [CompletedWalk] = []
    @State private var stats: WalkStats = .zero
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                Text("Your Walks").font(AlongFont.walkScreenHeading).foregroundStyle(AlongColor.textPrimary)
                if stats.walks > 0 {
                    Text("\(stats.walks) \(stats.walks == 1 ? "walk" : "walks") completed").font(AlongFont.headline).foregroundStyle(AlongColor.textPrimary)
                    Text("\(DistanceFormat.miles(Double(stats.distanceMeters))) walked · \(DistanceFormat.duration(stats.durationSeconds)) walking together")
                        .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                    StatsRow(stats: stats)
                }
                if walks.isEmpty && loaded {
                    AlongEmptyState(title: "No walks yet.", message: "When you and a walking buddy both finish a walk, it shows up here.")
                } else {
                    ForEach(walks) { walk in
                        CompletedWalkCard(walk: walk) { show, reveal in
                            Task {
                                try? await store.walks.setMemoryPrefs(sessionID: walk.id, showOnProfile: show, revealPartner: reveal)
                                await load()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.bottom, AlongSpacing.xl)
        }
        .alongScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        walks = (try? await store.walks.history()) ?? walks
        stats = (try? await store.walks.stats()) ?? stats
        loaded = true
    }
}

struct CompletedWalkCard: View {
    let walk: CompletedWalk
    let onPrefs: (_ showOnProfile: Bool?, _ revealPartner: Bool?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(walk.title).font(AlongFont.walkCardTitle).foregroundStyle(AlongColor.textPrimary)
                Spacer()
                Menu {
                    Toggle("Count in my public walk total", isOn: Binding(get: { walk.showOnProfile }, set: { onPrefs($0, nil) }))
                    Toggle("Remember who I walked with", isOn: Binding(get: { walk.revealPartner }, set: { onPrefs(nil, $0) }))
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(AlongColor.textTertiary).frame(width: 44, height: 44)
                }
                .padding(.trailing, -10).padding(.top, -10)
                .accessibilityLabel("Privacy options for this walk")
            }
            Text(walk.startedAt.formatted(date: .long, time: .omitted)).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            Text("\(DistanceFormat.duration(walk.durationSeconds)) · \(DistanceFormat.miles(Double(walk.distanceMeters)))")
                .font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
            HStack(spacing: 6) {
                if let partner = walk.partnerName { AlongChip(title: "with \(partner)") }
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
        .accessibilityElement(children: .combine)
    }
}
