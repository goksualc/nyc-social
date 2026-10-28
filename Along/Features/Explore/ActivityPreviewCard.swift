import SwiftUI

/// Compact card that rises from the bottom when a map marker is tapped.
struct ActivityPreviewCard: View {
    let activity: Activity
    let host: User?
    var now: Date = .now
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack(alignment: .top, spacing: AlongSpacing.sm) {
                if let host { AlongProfileAvatar(user: host, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(AlongFont.headline)
                        .foregroundStyle(AlongColor.textPrimary)
                        .lineLimit(2)
                    Text("\(host?.firstName ?? "") · \(ActivityTime.summary(activity, now: now, separator: ", "))")
                        .font(AlongFont.subhead)
                        .foregroundStyle(AlongColor.textTertiary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AlongColor.textTertiary)
                        .frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
                        .contentShape(Rectangle())
                }
                .padding(.top, -10).padding(.trailing, -10)
                .accessibilityLabel("Close preview")
            }

            AlongDivider()

            Text(activity.publicLocationLabel)
                .font(AlongFont.bodyEmphasis)
                .foregroundStyle(AlongColor.textPrimary)

            HStack {
                Text("\(activity.detailLabel) · \(activity.spotsLabel)")
                    .font(AlongFont.subhead)
                    .foregroundStyle(AlongColor.textTertiary)
                Spacer()
                AlongSmallButton(title: "View Plan", filled: true, action: onOpen)
            }
        }
        .padding(AlongSpacing.md)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .alongFloatingShadow()
        .gesture(DragGesture(minimumDistance: 20).onEnded { if $0.translation.height > 40 { onClose() } })
    }
}
