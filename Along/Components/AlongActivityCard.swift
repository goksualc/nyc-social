import SwiftUI

/// The standard activity card used in the discovery list and the Plans screen.
struct AlongActivityCard: View {
    let activity: Activity
    let host: User?
    var now: Date = .now
    /// Replaces the spots label (e.g. "2 requests pending" on Plans).
    var statusText: String?
    var hostLabel: String?
    /// Shows a quiet "Manage Plan" style pill at the bottom of the card (the whole card is the tap target).
    var actionTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack(spacing: AlongSpacing.xs) {
                HStack(spacing: 5) {
                    Image(systemName: activity.kind.symbol).font(.system(size: 11, weight: .semibold))
                    Text(activity.kind.label).font(AlongFont.label)
                }
                .foregroundStyle(AlongColor.navy)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(AlongColor.surface, in: Capsule())
                if activity.visibility == .private {
                    Label("Private", systemImage: "lock").labelStyle(.titleAndIcon)
                        .font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
                }
                Spacer()
                Text(ActivityTime.summary(activity, now: now))
                    .font(AlongFont.subheadEmphasis)
                    .foregroundStyle(AlongColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(AlongFont.headline)
                    .foregroundStyle(AlongColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(activity.publicLocationLabel)
                    .font(AlongFont.subhead)
                    .foregroundStyle(AlongColor.textTertiary)
            }

            AlongDivider()

            HStack(spacing: AlongSpacing.xs) {
                if let host { AlongProfileAvatar(user: host, size: 26) }
                Text(hostLabel ?? host?.firstName ?? "")
                    .font(AlongFont.subhead)
                    .foregroundStyle(AlongColor.textPrimary)
                Spacer()
                Text(statusText ?? activity.spotsLabel)
                    .font(AlongFont.subheadEmphasis)
                    .foregroundStyle(statusText == nil && activity.isFull ? AlongColor.textSecondary : AlongColor.navy)
            }

            if let actionTitle {
                Text(actionTitle)
                    .font(AlongFont.subheadEmphasis)
                    .foregroundStyle(AlongColor.navy)
                    .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch - 4)
                    .background(AlongColor.surface, in: Capsule())
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
        .contentShape(RoundedRectangle(cornerRadius: AlongRadius.card))
        .accessibilityElement(children: .combine)
    }
}
