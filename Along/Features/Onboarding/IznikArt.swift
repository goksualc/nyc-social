import SwiftUI
import UIKit

/// Pieces of the Iznik tile panel (`IznikPanel`, the project's own artwork from public/images/paint.jpg), cropped once and cached.
/// Nothing is redrawn or recoloured: every crop is a window onto the original image.
@MainActor
enum IznikArt {
    private static let panel = UIImage(named: "IznikPanel")
    private static var cache: [String: UIImage] = [:]

    /// Crop in the panel's own pixel space (1152 × 2048).
    private static func crop(_ key: String, _ rect: CGRect, mirrored: Bool = false) -> UIImage? {
        if let hit = cache[key] { return hit }
        guard let panel, let cg = panel.cgImage?.cropping(to: rect) else { return nil }
        var image = UIImage(cgImage: cg, scale: 1, orientation: .up)
        if mirrored, let flipped = image.cgImage { image = UIImage(cgImage: flipped, scale: 1, orientation: .upMirrored) }
        cache[key] = image
        return image
    }

    /// The white floral field in the middle of the panel.
    static var field: UIImage? { crop("field", CGRect(x: 150, y: 170, width: 850, height: 1130)) }
    /// A strip of the turquoise scroll border, used to dress the arch.
    static var borderStrip: UIImage? { crop("strip", CGRect(x: 0, y: 150, width: 128, height: 1700)) }
    /// The panel's top-left corner ornament (the top-right one is its mirror).
    static var corner: UIImage? { crop("corner", CGRect(x: 0, y: 0, width: 360, height: 360)) }
    static var cornerMirrored: UIImage? { crop("cornerM", CGRect(x: 0, y: 0, width: 360, height: 360), mirrored: true) }
    /// The panel's bottom scroll border.
    static var bottomBand: UIImage? { crop("band", CGRect(x: 0, y: 1886, width: 1152, height: 160)) }
}

/// A pointed (Ottoman-style) arch, straight sides with a gently peaked top.
struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let shoulder = h * 0.40
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + shoulder))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + shoulder * 0.42),
                   control2: CGPoint(x: rect.minX + w * 0.30, y: rect.minY + shoulder * 0.16))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + shoulder),
                   control1: CGPoint(x: rect.maxX - w * 0.30, y: rect.minY + shoulder * 0.16),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + shoulder * 0.42))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The landing page's main illustration: the floral field inside an arch whose frame is the panel's own turquoise border.
struct IznikArch: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frame: CGFloat = max(18, w * 0.105)
            // Whole number of border tiles across the width, so the left and right frames line up.
            let tiles = max((w / frame).rounded(), 1)
            let tileWidth = w / tiles
            ZStack {
                if let strip = IznikArt.borderStrip {
                    ArchShape().fill(ImagePaint(image: Image(uiImage: strip), scale: tileWidth / strip.size.width))
                }
                if let field = IznikArt.field {
                    Image(uiImage: field).resizable().scaledToFill()
                        .frame(width: w - tileWidth * 2, height: geo.size.height - tileWidth)
                        .clipShape(ArchShape())
                        .frame(width: w, height: geo.size.height, alignment: .bottom)
                }
                ArchShape().stroke(AlongColor.navy, lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A subtle ornament in the top-left or top-right corner. Multiply blending lets the tile's white fall away into Along's off-white.
struct IznikCorner: View {
    var mirrored = false
    var body: some View {
        if let image = mirrored ? IznikArt.cornerMirrored : IznikArt.corner {
            Image(uiImage: image).resizable().scaledToFit()
                // Fade the crop out toward the screen so it reads as an ornament, not a block.
                .mask(RadialGradient(colors: [.black, .black, .clear], center: mirrored ? .topTrailing : .topLeading,
                                     startRadius: 28, endRadius: 100))
                .blendMode(.multiply)
                .opacity(0.9)
                .accessibilityHidden(true)
        }
    }
}

/// The scroll border along the bottom edge.
struct IznikBand: View {
    var body: some View {
        if let image = IznikArt.bottomBand {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}
