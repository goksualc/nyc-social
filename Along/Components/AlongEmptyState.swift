import SwiftUI

struct AlongEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AlongSpacing.sm) {
            Text(title)
                .font(AlongFont.title)
                .foregroundStyle(AlongColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AlongFont.subhead)
                .foregroundStyle(AlongColor.textTertiary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                AlongButton(title: actionTitle, style: .primary, fullWidth: false, action: action)
                    .padding(.top, AlongSpacing.sm)
            }
        }
        .padding(AlongSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
