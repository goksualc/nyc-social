import SwiftUI

/// Small, quiet map marker: navy with a walking figure for walks, white with a laptop for cowork.
struct AlongMapMarker: View {
    let kind: ActivityKind
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(kind == .walk ? AlongColor.navy : AlongColor.white)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(kind == .walk ? AlongColor.white : AlongColor.navy, lineWidth: 2))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind == .walk ? AlongColor.white : AlongColor.navy)
        }
        .scaleEffect(isSelected ? 1.22 : 1)
        .alongAnimation(.alongQuick, value: isSelected)
        .frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
        .contentShape(Circle())
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
