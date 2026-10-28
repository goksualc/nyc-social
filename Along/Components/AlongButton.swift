import SwiftUI

struct AlongButton: View {
    enum Style { case primary, secondary, ghost, destructive }

    let title: String
    var symbol: String?
    var style: Style = .primary
    var isLoading = false
    var fullWidth = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: AlongSpacing.xs) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(AlongFont.bodyEmphasis)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: style == .ghost ? AlongSize.minTouch : AlongSize.button)
            .padding(.horizontal, fullWidth ? 0 : AlongSpacing.lg)
            .background(background, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
            .overlay {
                if style == .secondary || style == .destructive {
                    RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous).stroke(AlongColor.border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AlongPressStyle())
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch style {
        case .primary: AlongColor.white
        case .secondary, .ghost: AlongColor.navy
        case .destructive: AlongColor.destructive
        }
    }

    private var background: Color {
        switch style {
        case .primary: AlongColor.navy
        case .secondary, .destructive: AlongColor.white
        case .ghost: .clear
        }
    }
}

/// Compact pill button for in-row actions (Accept / Decline / View Plan).
struct AlongSmallButton: View {
    let title: String
    var filled = false
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role) {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(AlongFont.subheadEmphasis)
                .foregroundStyle(filled ? AlongColor.white : AlongColor.navy)
                .padding(.horizontal, AlongSpacing.md)
                .frame(minHeight: AlongSize.minTouch)
                .background(filled ? AlongColor.navy : AlongColor.white, in: Capsule())
                .overlay(Capsule().stroke(filled ? .clear : AlongColor.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(AlongPressStyle())
    }
}
