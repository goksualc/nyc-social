import SwiftUI

/// The read-only profile body shared by "my profile" and other people's profiles.
/// Friendly and informative; no follower counts, rankings or compatibility scores.
struct DetailedProfileView: View {
    let user: User
    /// Walk totals, shown only when the person chose to share them (or it's my own profile).
    var stats: WalkStats?
    var isMine = false

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            header
            let about = aboutLines
            if !about.isEmpty {
                ProfileSection(title: "About") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(about, id: \.1) { symbol, text in
                            Label { Text(text).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary) }
                                icon: { Image(systemName: symbol).foregroundStyle(AlongColor.navy).frame(width: 22) }
                        }
                    }
                }
            }
            if !user.hobbies.isEmpty { ProfileSection(title: "Interests") { HobbyPills(items: user.hobbies) } }
            let talk = user.discussionTopics.map(\.rawValue) + user.conversationCustom
            if !talk.isEmpty { ProfileSection(title: "Let's talk about") { HobbyPills(items: talk) } }
            if hasWalkingPreferences { ProfileSection(title: "Walking preferences") { preferences } }
            if let stats, stats.walks > 0 || isMine {
                ProfileSection(title: "Walking history") { StatsRow(stats: stats) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: AlongSpacing.sm) {
            AlongProfileAvatar(user: user, size: 112)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(user.firstName).font(AlongFont.profileName).foregroundStyle(AlongColor.textPrimary)
                if let age = user.age { Text("\(age)").font(.system(.title3)).foregroundStyle(AlongColor.textTertiary) }
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Text(user.neighborhood).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            if !user.bio.isEmpty {
                Text(user.bio).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                    .multilineTextAlignment(.center).padding(.horizontal, AlongSpacing.md)
            }
            SocialLinksView(user: user)
        }
        .frame(maxWidth: .infinity)
    }

    private var aboutLines: [(String, String)] {
        var out: [(String, String)] = []
        if let o = user.occupation, !o.isEmpty { out.append(("briefcase", o)) }
        if let u = user.university, !u.isEmpty { out.append(("graduationcap", u)) }
        if !user.languages.isEmpty { out.append(("character.bubble", user.languages.joined(separator: ", "))) }
        return out
    }

    private var hasWalkingPreferences: Bool {
        user.pacePreference != nil || user.preferredDuration != nil || !user.favoriteNeighborhoods.isEmpty
    }

    private var preferences: some View {
        FlowLayout(spacing: 8) {
            if let p = user.pacePreference { AlongChip(title: "\(p.rawValue) pace", symbol: "figure.walk") }
            if let d = user.preferredDuration { AlongChip(title: WalkDuration.label(d), symbol: "clock") }
            ForEach(user.favoriteNeighborhoods, id: \.self) { AlongChip(title: $0, symbol: "mappin") }
        }
    }
}

struct StatsRow: View {
    let stats: WalkStats
    var body: some View {
        HStack(spacing: 0) {
            stat("\(stats.walks)", stats.walks == 1 ? "walk" : "walks")
            divider
            stat(DistanceFormat.miles(Double(stats.distanceMeters)), "walked")
            divider
            stat(DistanceFormat.duration(stats.durationSeconds), "together")
        }
        .padding(.vertical, AlongSpacing.sm)
        .frame(maxWidth: .infinity)
        .alongCard()
        .accessibilityElement(children: .combine)
    }
    private var divider: some View { Rectangle().fill(AlongColor.border).frame(width: 1, height: 32) }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
            Text(label).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
