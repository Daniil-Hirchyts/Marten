import AppKit
import Foundation

public final class ThumbnailGenerator {
    private let maxPixelSize: CGFloat

    public init(maxPixelSize: CGFloat = 240) {
        self.maxPixelSize = maxPixelSize
    }

    public func generateThumbnail(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let maxDimension = max(width, height)
        guard maxDimension > 0 else { return nil }

        let scale = min(1.0, maxPixelSize / CGFloat(maxDimension))
        let targetWidth = max(1, Int(CGFloat(width) * scale))
        let targetHeight = max(1, Int(CGFloat(height) * scale))

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let resizedImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: resizedImage)
        return rep.representation(using: .png, properties: [:])
    }
}
