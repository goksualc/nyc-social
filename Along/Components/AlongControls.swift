import SwiftUI

/// Minimal two-or-more-way segmented control with a sliding navy indicator.
struct AlongSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    /// Optional count badge per segment.
    var badges: [Int] = []
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    Haptics.selection()
                    alongWithAnimation(.alongQuick) { selection = i }
                } label: {
                    HStack(spacing: 6) {
                        Text(options[i]).font(AlongFont.subheadEmphasis)
                        if i < badges.count, badges[i] > 0 {
                            Text("\(badges[i])")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(selection == i ? AlongColor.navy : AlongColor.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(selection == i ? AlongColor.white : AlongColor.navy, in: Capsule())
                        }
                    }
                    .foregroundStyle(selection == i ? AlongColor.white : AlongColor.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch - 4)
                    .background {
                        if selection == i {
                            Capsule().fill(AlongColor.navy).matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AlongColor.surface, in: Capsule())
    }
}

/// Small rounded tag, optionally selectable (interests).
struct AlongChip: View {
    let title: String
    var isSelected = false
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(AlongFont.subheadEmphasis)
        }
        .foregroundStyle(isSelected ? AlongColor.white : AlongColor.textPrimary)
        .padding(.horizontal, AlongSpacing.sm + 2)
        .padding(.vertical, 7)
        .background(isSelected ? AlongColor.navy : AlongColor.surface, in: Capsule())
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowH = max(rowH, size.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), origins)
    }
}

/// Uppercase-free, quiet section label.
struct AlongSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AlongFont.label)
            .foregroundStyle(AlongColor.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct AlongDivider: View {
    var body: some View { Rectangle().fill(AlongColor.border).frame(height: 1) }
}

/// Label + value pair used in details ("Pace  Casual").
struct AlongInfoRow: View {
    let symbol: String
    let text: String
    var secondary: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AlongSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AlongColor.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                if let secondary { Text(secondary).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
