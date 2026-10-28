import SwiftUI

// MARK: - Colour

extension Color {
    /// `Color(hex: 0x1C2343)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Centralised colour tokens. The palette is deliberately small and taken from the brand logos.
enum AlongColor {
    static let navy = Color(hex: 0x1C2343)
    static let offWhite = Color(hex: 0xFAF9F6)
    static let white = Color.white
    static let textPrimary = Color(hex: 0x202020)
    static let textSecondary = Color(hex: 0x858585)
    static let border = Color(hex: 0xE9E9E7)
    static let surface = Color(hex: 0xF3F3F0)

    /// Secondary text that must still pass 4.5:1 on white at small sizes.
    static let textTertiary = Color(hex: 0x6E6E6E)
    /// Used only for destructive confirmations — the one place a warm hue earns its keep.
    static let destructive = Color(hex: 0xA13B2F)

    /// Muted tones used behind monogram avatars. Deliberately close to the navy/stone palette.
    static let avatarTones: [Color] = [
        Color(hex: 0xDCE0EC), Color(hex: 0xE8E3D8), Color(hex: 0xDDE5DF),
        Color(hex: 0xEBDDD8), Color(hex: 0xE0DCEA), Color(hex: 0xE4E4E0),
    ]
}

// MARK: - Typography

/// SF Pro for interface text. A serif (New York) is used for large display headings only,
/// echoing the wordmark without ever replacing it.
enum AlongFont {
    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let title = Font.system(.title2, design: .serif, weight: .semibold)
    static let screenTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)

    static let heading = Font.system(.title3, weight: .semibold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body, weight: .medium)
    static let subhead = Font.system(.subheadline)
    static let subheadEmphasis = Font.system(.subheadline, weight: .medium)
    static let caption = Font.system(.caption)
    static let label = Font.system(.footnote, weight: .medium)
}

// MARK: - Spacing & shape

enum AlongSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Horizontal screen margin.
    static let gutter: CGFloat = 20
}

enum AlongRadius {
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let sheet: CGFloat = 28
}

enum AlongSize {
    /// Apple HIG minimum touch target.
    static let minTouch: CGFloat = 44
    static let button: CGFloat = 54
}
