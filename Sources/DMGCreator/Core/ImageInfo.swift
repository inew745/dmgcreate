import Foundation
import ImageIO
import CoreGraphics

/// Reads an image's dimensions without decoding the whole thing.
enum ImageInfo {

    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return nil }

        let widthKey = kCGImagePropertyPixelWidth as String
        let heightKey = kCGImagePropertyPixelHeight as String
        guard let width = properties[widthKey] as? NSNumber,
              let height = properties[heightKey] as? NSNumber
        else { return nil }

        return CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
    }

    /// Size in points. A plain 1x image is one pixel per point; a file named
    /// `…@2x.…` is half its pixel size.
    static func pointSize(of url: URL) -> CGSize? {
        guard let pixels = pixelSize(of: url) else { return nil }
        let scale: CGFloat = url.deletingPathExtension().lastPathComponent.hasSuffix("@2x") ? 2 : 1
        return CGSize(width: pixels.width / scale, height: pixels.height / scale)
    }

    static func describe(_ url: URL) -> String {
        guard let pixels = pixelSize(of: url) else { return url.lastPathComponent }
        return "\(url.lastPathComponent) — \(Int(pixels.width))×\(Int(pixels.height))"
    }
}
