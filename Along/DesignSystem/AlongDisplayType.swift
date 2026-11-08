import SwiftUI
import UIKit

/// The editorial display face for large headings on the landing, authentication and onboarding screens.
///
/// - The bundled file is `Fonts/SlashSignature-Regular.ttf`, registered through `UIAppFonts` in Info.plist.
/// - Fonts are looked up by *PostScript* name, which is not the filename: `SlashSignaturePersonalUseOn-R`.
/// - Change `postScriptName` (and the file) to swap the face everywhere; nothing else refers to it.
/// - If the font fails to load, headings fall back to the existing serif so no screen is left unstyled.
/// - Single weight on purpose: never add bold on top of it (that would be synthetic).
enum AlongDisplayType {
    static let postScriptName = "SlashSignaturePersonalUseOn-R"
    static var isAvailable: Bool { UIFont(name: postScriptName, size: 12) != nil }

    /// Dynamic-Type-aware UIFont (scales with the user's text size, relative to Large Title).
    static func uiFont(size: CGFloat) -> UIFont {
        let base = UIFont(name: postScriptName, size: size)
            ?? UIFont.systemFont(ofSize: size * 0.8, weight: .semibold).withDesign(.serif)
        return UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: base, maximumPointSize: size * 1.7)
    }
}

private extension UIFont {
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        guard let d = fontDescriptor.withDesign(design) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}

/// A large display heading. Wrapped in UIKit because SwiftUI can't tighten this script face's tall line height,
/// and because its swashes overhang the line box (SwiftUI's `Text` clips the first letter of wrapped lines).
/// Wraps instead of truncating, scales with Dynamic Type, and shrinks a little on narrow phones.
struct AlongDisplayHeading: View {
    let text: String
    var size: CGFloat = 44
    var color: Color = AlongColor.textPrimary
    var alignment: NSTextAlignment = .left

    /// Room for the swashes on each side; the view is pulled back by the same amount so text still aligns to the margin.
    private let overhang: CGFloat = 14

    init(_ text: String, size: CGFloat = 44, color: Color = AlongColor.textPrimary, alignment: NSTextAlignment = .left) {
        self.text = text; self.size = size; self.color = color; self.alignment = alignment
    }

    var body: some View {
        DisplayLabel(text: text, size: size, color: UIColor(color), alignment: alignment, inset: overhang)
            .padding(.horizontal, -overhang)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DisplayLabel: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: UIColor
    let alignment: NSTextAlignment
    let inset: CGFloat

    /// Everything that affects how the heading looks. If none of it changed, SwiftUI's re-render is a no-op.
    struct Style: Equatable {
        var text: String
        var size: CGFloat
        var color: UIColor
        var alignment: NSTextAlignment
        var inset: CGFloat
        var category: UIContentSizeCategory
        var screenWidth: CGFloat
    }

    /// Remembers what is already on the label and the last measured size.
    /// Auth screens re-render on every keystroke and on every frame of the keyboard animation; without this the heading
    /// rebuilt its attributed string and re-ran a full text layout each time, which made typing stutter.
    final class Coordinator {
        var applied: Style?
        var measured: (style: Style, width: CGFloat, size: CGSize)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InsetLabel {
        let label = InsetLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func style(for label: UIView) -> Style {
        Style(text: text, size: size, color: color, alignment: alignment, inset: inset,
              category: label.traitCollection.preferredContentSizeCategory, screenWidth: UIScreen.main.bounds.width)
    }

    func updateUIView(_ label: InsetLabel, context: Context) {
        let current = style(for: label)
        guard context.coordinator.applied != current else { return }     // nothing changed: do no work
        context.coordinator.applied = current
        label.insets = UIEdgeInsets(top: 6, left: inset, bottom: 10, right: inset)
        // Narrow phones (SE, mini) get a slightly smaller face so long headlines don't run to extra lines.
        let scale = min(max(current.screenWidth / 393, 0.82), 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 0.74
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: AlongDisplayType.uiFont(size: size * scale), .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InsetLabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let current = style(for: uiView)
        if let m = context.coordinator.measured, m.style == current, abs(m.width - width) < 0.5 { return m.size }
        // Make sure the label carries this style before measuring it.
        if context.coordinator.applied != current { updateUIView(uiView, context: context) }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: ceil(fitted.height))
        context.coordinator.measured = (current, width, size)
        return size
    }
}

private final class InsetLabel: UILabel {
    var insets: UIEdgeInsets = .zero { didSet { setNeedsDisplay(); invalidateIntrinsicContentSize() } }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines n: Int) -> CGRect {
        let r = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: n)
        return CGRect(x: r.minX - insets.left, y: r.minY - insets.top, width: r.width + insets.left + insets.right, height: r.height + insets.top + insets.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = CGSize(width: max(size.width - insets.left - insets.right, 1), height: size.height)
        let s = super.sizeThatFits(inner)
        return CGSize(width: size.width, height: s.height + insets.top + insets.bottom)
    }
}
