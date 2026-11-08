import SwiftUI

/// A text field in the same style as `AlongTextField`, with secure entry and the keyboard traits auth forms need.
struct AuthField: View {
    let label: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Text(label).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            Group {
                if isSecure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .font(AlongFont.body)
            .foregroundStyle(AlongColor.textPrimary)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .focused($focused)
            .padding(.horizontal, AlongSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AlongSize.button, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous)
                    .stroke(focused ? AlongColor.navy : AlongColor.border, lineWidth: focused ? 1.5 : 1))
            .accessibilityLabel(label)
        }
    }
}

/// Inline error / hint line used across the auth screens.
struct AuthMessage: View {
    let text: String
    var isError = true
    var body: some View {
        Text(text)
            .font(AlongFont.subhead)
            .foregroundStyle(isError ? AlongColor.destructive : AlongColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(isError ? [] : .isStaticText)
    }
}

/// Shared page chrome: serif title, optional subtitle, scrolling content, pinned footer.
struct AuthScaffold<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                    AlongDisplayHeading(title, size: 44)
                    if let subtitle {
                        Text(subtitle).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary)
                    }
                }
                .padding(.top, AlongSpacing.lg)
                content
            }
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .padding(.bottom, AlongSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .alongScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, AlongSpacing.gutter + 4)
                .padding(.vertical, AlongSpacing.sm)
                .background(AlongColor.offWhite.ignoresSafeArea(edges: .bottom))
        }
    }
}
