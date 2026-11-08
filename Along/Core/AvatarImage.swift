import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever the photo picker hands over (HEIC, a 12-megapixel JPEG, a screenshot PNG…) into a small square JPEG.
enum AvatarImage {
    static let side: CGFloat = 512
    /// The `avatars` bucket refuses files above 2 MB; aim far below that so uploads are quick on cellular.
    static let targetBytes = 350_000

    /// Downsamples with ImageIO (never decodes the full-size bitmap), applies the photo's orientation, centre-crops to a
    /// square, and lowers the JPEG quality until the file is small. Returns nil if the data isn't an image.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,          // honours EXIF orientation, so portraits aren't sideways
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = side / min(w, h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true                                           // JPEG has no alpha; avoid black corners from PNGs
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: (side - w * scale) / 2, y: (side - h * scale) / 2, width: w * scale, height: h * scale))
        }
        for quality in stride(from: 0.85, through: 0.4, by: -0.15) {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= targetBytes { return jpeg }
        }
        return rendered.jpegData(compressionQuality: 0.4)
    }
}
