import SwiftUI
import UIKit

// MARK: - Haptics

@MainActor
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Motion

extension Animation {
    /// The one easing used across the app so motion feels consistent and calm.
    static let along = Animation.smooth(duration: 0.35)
    static let alongQuick = Animation.smooth(duration: 0.22)
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_, value:)` that is skipped when Reduce Motion is enabled.
    func alongAnimation<V: Equatable>(_ animation: Animation = .along, value: V) -> some View {
        modifier(ReducedMotionAnimation(animation: animation, value: value))
    }
}

/// Runs a state change with animation unless Reduce Motion is on.
@MainActor
func alongWithAnimation(_ animation: Animation = .along, _ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled { body() } else { withAnimation(animation, body) }
}

// MARK: - Button feedback

/// Soft press feedback: a tiny scale and dim, no bounce.
struct AlongPressStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.alongQuick, value: configuration.isPressed)
    }
}

// MARK: - Surfaces

extension View {
    /// White card with the consistent corner radius and a hairline border.
    func alongCard(radius: CGFloat = AlongRadius.card, fill: Color = AlongColor.white) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
    }

    /// The only shadow in the app: very soft, used on floating map UI.
    func alongFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    func alongScreenBackground() -> some View {
        background(AlongColor.offWhite.ignoresSafeArea())
    }
}

// MARK: - UIKit appearance

enum AlongAppearance {
    static func configure() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(AlongColor.offWhite)
        tab.shadowColor = UIColor(AlongColor.border)
        let normal = UIColor(AlongColor.textTertiary)
        let selected = UIColor(AlongColor.navy)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(AlongColor.offWhite)
        nav.shadowColor = .clear
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        nav.titleTextAttributes = [.foregroundColor: UIColor(AlongColor.textPrimary), .font: titleFont]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(AlongColor.navy)
    }
}
