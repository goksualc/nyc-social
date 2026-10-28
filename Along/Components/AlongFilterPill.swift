import SwiftUI

struct AlongFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(AlongFont.subheadEmphasis)
                .foregroundStyle(isSelected ? AlongColor.white : AlongColor.textPrimary)
                .padding(.horizontal, AlongSpacing.md)
                .frame(minHeight: AlongSize.minTouch - 8)
                .background(isSelected ? AlongColor.navy : AlongColor.white, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? .clear : AlongColor.border, lineWidth: 1))
                .alongFloatingShadow()
                .frame(minHeight: AlongSize.minTouch)
                .contentShape(Capsule())
        }
        .buttonStyle(AlongPressStyle(scale: 0.96))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
