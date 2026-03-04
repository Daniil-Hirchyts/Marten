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

    public init(maxPixelSize: CGFloat = 1024) {
        self.maxPixelSize = maxPixelSize
    }

    public func generateThumbnail(from data: Data) -> Result<Data, ThumbnailError> {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            )
        else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.cgImageSourceFailed.description)")
            return .failure(.cgImageSourceFailed)
        }

        return generateThumbnail(from: source)
    }

    public func generateThumbnail(fromFileURL url: URL) -> Result<Data, ThumbnailError> {
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            )
        else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.cgImageSourceFailed.description)")
            return .failure(.cgImageSourceFailed)
        }

        return generateThumbnail(from: source)
    }

    private func generateThumbnail(from source: CGImageSource) -> Result<Data, ThumbnailError> {
        guard CGImageSourceGetCount(source) > 0 else {
            Logger.thumbnails.warning(
                "Thumbnail generation failed: \(ThumbnailError.invalidImageData.description)")
            return .failure(.invalidImageData)
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
