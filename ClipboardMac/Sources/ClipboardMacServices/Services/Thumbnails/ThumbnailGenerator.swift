import AppKit
import Foundation
import OSLog

/// Errors that can occur during thumbnail generation
public enum ThumbnailError: Error, CustomStringConvertible {
    case invalidImageData
    case cgImageConversionFailed
    case invalidDimensions
    case colorSpaceUnavailable
    case contextCreationFailed
    case resizeFailed
    case encodingFailed

    public var description: String {
        switch self {
        case .invalidImageData:
            return "Failed to create NSImage from data"
        case .cgImageConversionFailed:
            return "Failed to convert NSImage to CGImage"
        case .invalidDimensions:
            return "Image has invalid dimensions (zero or negative)"
        case .colorSpaceUnavailable:
            return "Could not obtain or create color space"
        case .contextCreationFailed:
            return "Failed to create CGContext for resizing"
        case .resizeFailed:
            return "Failed to create resized image from context"
        case .encodingFailed:
            return "Failed to encode thumbnail as PNG"
        }
    }
}

public final class ThumbnailGenerator {
    private let maxPixelSize: CGFloat

    public init(maxPixelSize: CGFloat = 240) {
        self.maxPixelSize = maxPixelSize
    }

    public func generateThumbnail(from data: Data) -> Result<Data, ThumbnailError> {
        guard let image = NSImage(data: data) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.invalidImageData.description)")
            return .failure(.invalidImageData)
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.cgImageConversionFailed.description)"
            )
            return .failure(.cgImageConversionFailed)
        }

        let width = cgImage.width
        let height = cgImage.height
        let maxDimension = max(width, height)
        guard maxDimension > 0 else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.invalidDimensions.description)")
            return .failure(.invalidDimensions)
        }

        let scale = min(1.0, maxPixelSize / CGFloat(maxDimension))
        let targetWidth = max(1, Int(CGFloat(width) * scale))
        let targetHeight = max(1, Int(CGFloat(height) * scale))

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.colorSpaceUnavailable.description)")
            return .failure(.colorSpaceUnavailable)
        }

        guard
            let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.contextCreationFailed.description)")
            return .failure(.contextCreationFailed)
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let resizedImage = context.makeImage() else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.resizeFailed.description)")
            return .failure(.resizeFailed)
        }

        let rep = NSBitmapImageRep(cgImage: resizedImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.encodingFailed.description)")
            return .failure(.encodingFailed)
        }

        return .success(pngData)
    }
}

extension ThumbnailGenerator: Sendable {}
