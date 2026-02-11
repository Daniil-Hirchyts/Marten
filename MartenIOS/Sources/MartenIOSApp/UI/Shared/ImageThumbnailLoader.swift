import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import MartenCore

#if canImport(UIKit)
import UIKit
typealias ThumbnailPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias ThumbnailPlatformImage = NSImage
#endif

@MainActor
final class ImageThumbnailLoader {
    static let shared = ImageThumbnailLoader()

    private let cache = NSCache<NSString, ThumbnailPlatformImage>()

    private init() {
        cache.countLimit = 350
    }

    func loadThumbnail(for item: ClipItem, maxPixelSize: CGFloat = 900) async -> ThumbnailPlatformImage? {
        guard item.itemTypeValue == .image else { return nil }

        let cacheKey = cacheKey(for: item)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let snapshot = makeSnapshot(for: item)

        let image = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let resolved = loadDownsampledImage(snapshot: snapshot, maxPixelSize: maxPixelSize)
                continuation.resume(returning: resolved)
            }
        }

        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        }

        return image
    }

    private func cacheKey(for item: ClipItem) -> String {
        let version = Int64(item.modifiedAt.timeIntervalSince1970 * 1000)
        return "image-thumbnail-\(item.id.uuidString)-\(version)"
    }

    private func makeSnapshot(for item: ClipItem) -> ThumbnailSnapshot {
        let representations = (item.representations ?? []).map {
            ThumbnailRepresentation(
                kind: $0.kindValue,
                binaryData: $0.binaryData,
                assetRef: $0.assetRef,
                fileExtension: $0.fileExtension,
                textData: $0.textData
            )
        }

        return ThumbnailSnapshot(
            thumbnailPath: item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            representations: representations
        )
    }
}

private struct ThumbnailSnapshot {
    let thumbnailPath: String?
    let representations: [ThumbnailRepresentation]
}

private struct ThumbnailRepresentation {
    let kind: RepresentationKind
    let binaryData: Data?
    let assetRef: UUID?
    let fileExtension: String?
    let textData: Data?
}

private func loadDownsampledImage(
    snapshot: ThumbnailSnapshot,
    maxPixelSize: CGFloat
) -> ThumbnailPlatformImage? {
    if let thumbnailPath = snapshot.thumbnailPath,
        !thumbnailPath.isEmpty,
        let image = downsampleImage(atPath: thumbnailPath, maxPixelSize: maxPixelSize)
    {
        return image
    }

    for representation in snapshot.representations {
        switch representation.kind {
        case .png, .jpeg, .tiff, .pdf:
            if let data = representation.binaryData,
                let image = downsampleImage(from: data, maxPixelSize: maxPixelSize)
            {
                return image
            }

            if let assetRef = representation.assetRef {
                let path = AssetStore.shared.urlForAsset(
                    assetRef,
                    fileExtension: representation.fileExtension
                ).path
                if let image = downsampleImage(atPath: path, maxPixelSize: maxPixelSize) {
                    return image
                }
            }
        case .fileURL:
            if let textData = representation.textData,
                let path = String(data: textData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty,
                let image = downsampleImage(atPath: path, maxPixelSize: maxPixelSize)
            {
                return image
            }
        default:
            continue
        }
    }

    return nil
}

private func downsampleImage(atPath path: String, maxPixelSize: CGFloat) -> ThumbnailPlatformImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }

    return downsampleImage(from: source, maxPixelSize: maxPixelSize)
}

private func downsampleImage(from data: Data, maxPixelSize: CGFloat) -> ThumbnailPlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }

    return downsampleImage(from: source, maxPixelSize: maxPixelSize)
}

private func downsampleImage(from source: CGImageSource, maxPixelSize: CGFloat) -> ThumbnailPlatformImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
    ]

    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }

    #if canImport(UIKit)
    return UIImage(cgImage: thumbnail)
    #elseif canImport(AppKit)
    return NSImage(cgImage: thumbnail, size: .zero)
    #else
    return nil
    #endif
}
