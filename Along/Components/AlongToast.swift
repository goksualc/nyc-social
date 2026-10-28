import SwiftUI

/// Subtle confirmation capsule shown at the top of the screen (clear of one-handed controls).
struct AlongToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: AlongSpacing.xs) {
            Image(systemName: toast.symbol).font(.system(size: 14, weight: .semibold))
            Text(toast.text).font(AlongFont.subheadEmphasis).lineLimit(2)
        }
        .foregroundStyle(AlongColor.white)
        .padding(.horizontal, AlongSpacing.md)
        .padding(.vertical, AlongSpacing.sm)
        .background(AlongColor.navy, in: Capsule())
        .alongFloatingShadow()
        .accessibilityElement(children: .combine)
    }
}

private struct ToastOverlay: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = store.toast {
                AlongToastView(toast: toast)
                    .padding(.top, AlongSpacing.xs)
                    .padding(.horizontal, AlongSpacing.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .onAppear { UIAccessibility.post(notification: .announcement, argument: toast.text) }
                    .onTapGesture { store.dismissToast() }
            }
        }
    }
}

extension View {
    /// Attach to every presentation root (tabs and each sheet) so confirmations are visible everywhere.
    func alongToasts() -> some View { modifier(ToastOverlay()) }
}
