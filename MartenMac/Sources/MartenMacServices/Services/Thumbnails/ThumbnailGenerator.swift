import AppKit
import Foundation
import OSLog

/// Errors that can occur during thumbnail generation
public enum ThumbnailError: Error, CustomStringConvertible {
    case invalidImageData
    case cgImageSourceFailed
    case thumbnailGenerationFailed
    case encodingFailed

    public var description: String {
        switch self {
        case .invalidImageData:
            return "Failed to create image source from data"
        case .cgImageSourceFailed:
            return "Failed to create CGImageSource"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.cgImageSourceFailed.description)")
            return .failure(.cgImageSourceFailed)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.thumbnailGenerationFailed.description)")
            return .failure(.thumbnailGenerationFailed)
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.encodingFailed.description)")
            return .failure(.encodingFailed)
        }

        return .success(pngData)
    }
}

extension ThumbnailGenerator: Sendable {}
