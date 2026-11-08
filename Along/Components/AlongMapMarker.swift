import SwiftUI

/// A floating rounded-square marker with a small stem. White with a navy glyph at rest; navy with a white glyph when selected.
struct AlongMapMarker: View {
    var isSelected = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "figure.walk")
                .font(.system(size: isSelected ? 20 : 17, weight: .semibold))
                .foregroundStyle(isSelected ? AlongColor.white : AlongColor.navy)
                .frame(width: isSelected ? 50 : 42, height: isSelected ? 50 : 42)
                .background(isSelected ? AlongColor.navy : AlongColor.white,
                            in: RoundedRectangle(cornerRadius: isSelected ? 16 : 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: isSelected ? 16 : 14, style: .continuous)
                    .stroke(isSelected ? AlongColor.white : AlongColor.border, lineWidth: isSelected ? 2 : 1))
                .shadow(color: .black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 10 : 6, y: isSelected ? 5 : 3)
            Capsule()
                .fill(isSelected ? AlongColor.navy : AlongColor.white)
                .frame(width: 3, height: isSelected ? 9 : 6)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .alongAnimation(.alongQuick, value: isSelected)
        .frame(minWidth: AlongSize.minTouch)
        .contentShape(Rectangle())
    }
}

/// Where a walk ends.
struct AlongRouteEndDot: View {
    var body: some View {
        Circle()
            .fill(AlongColor.white)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(AlongColor.navy, lineWidth: 2.5))
    }
}
