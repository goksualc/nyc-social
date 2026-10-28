import SwiftUI

/// The official brand assets, shown at their original proportions. Never recoloured, stretched or restyled.
struct AlongLogo: View {
    enum Variant { case navy, white }
    var variant: Variant = .navy
    var width: CGFloat = 180

    var body: some View {
        Image(variant == .navy ? "AlongLogo" : "AlongLogoWhite")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel("Along")
    }
}

/// The hand symbol alone (a template image so it can adopt a tint).
struct AlongMark: View {
    var size: CGFloat = 24
    var color: Color = AlongColor.navy

    var body: some View {
        Image("AlongMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityLabel("Along")
    }
}
