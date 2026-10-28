import SwiftUI

/// Labelled text input on a subtle surface.
struct AlongTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int> = 1...1
    var limit: Int?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Text(label).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            TextField(prompt, text: $text, axis: axis)
                .font(AlongFont.body)
                .foregroundStyle(AlongColor.textPrimary)
                .lineLimit(lines)
                .focused($focused)
                .padding(.horizontal, AlongSpacing.md)
                .padding(.vertical, AlongSpacing.sm + 2)
                .frame(minHeight: AlongSize.minTouch)
                .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous)
                        .stroke(focused ? AlongColor.navy : AlongColor.border, lineWidth: focused ? 1.5 : 1)
                )
                .onChange(of: text) { _, new in
                    if let limit, new.count > limit { text = String(new.prefix(limit)) }
                }
        }
    }
}

/// A tappable field that looks like `AlongTextField` — used for pickers that push a search screen.
struct AlongFieldRow: View {
    let label: String
    let value: String?
    var placeholder: String
    var symbol: String = "magnifyingglass"
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Text(label).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            Button(action: action) {
                HStack {
                    Text(value ?? placeholder)
                        .font(AlongFont.body)
                        .foregroundStyle(value == nil ? AlongColor.textSecondary : AlongColor.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(AlongColor.textSecondary)
                }
                .padding(.horizontal, AlongSpacing.md)
                .frame(minHeight: AlongSize.minTouch + 4)
                .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(AlongPressStyle())
        }
    }
}
