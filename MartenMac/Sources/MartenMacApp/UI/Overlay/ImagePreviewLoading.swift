import AppKit
import CoreData
import Foundation
import ImageIO
import MartenCore
    
struct ImagePreviewSourceSnapshot: Equatable, Sendable {
    private static let imageLikeFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "svg", "pdf",
    ]

    let kind: RepresentationKind
    let binaryData: Data?
    let assetRef: UUID?
    let fileExtension: String?
    let textData: Data?

    init(
        kind: RepresentationKind,
        binaryData: Data?,
        assetRef: UUID?,
        fileExtension: String?,
        textData: Data?
    ) {
        self.kind = kind
        self.binaryData = binaryData
        self.assetRef = assetRef
        self.fileExtension = fileExtension
        self.textData = textData
    }

    init(representation: ClipRepresentation) {
        self.init(
            kind: representation.kindValue,
            binaryData: representation.binaryData,
            assetRef: representation.assetRef,
            fileExtension: representation.fileExtension,
            textData: representation.textData
        )
    }

    var isRenderableImageKind: Bool {
        kind == .png
            || kind == .jpeg
            || kind == .tiff
            || kind == .pdf
            || (kind == .custom
                && normalizedFileExtension.map({ Self.imageLikeFileExtensions.contains($0) }) == true)
    }

    var assetFileURL: URL? {
        guard let assetRef else { return nil }
        return AssetStore.shared.existingURLForAsset(assetRef, fileExtension: fileExtension)
    }

    var fileURLRepresentation: URL? {
        guard let trimmedPath = normalizedTextPath, !trimmedPath.isEmpty else { return nil }

        if let url = URL(string: trimmedPath), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: trimmedPath)
    }

    var hasRecoverablePayload: Bool {
        assetRef != nil || (isRenderableImageKind && binaryData != nil) || fileURLRepresentation != nil
    }

    var cacheSignature: String {
        let assetSignature = assetRef?.uuidString ?? "none"
        let extensionSignature = normalizedFileExtension ?? "none"
        let pathSignature = normalizedTextPath ?? "none"
        let byteCount = binaryData?.count ?? 0
        return "\(kind.rawValue).\(assetSignature).\(extensionSignature).\(byteCount).\(pathSignature)"
    }

    private var normalizedFileExtension: String? {
        let trimmed = fileExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var normalizedTextPath: String? {
        guard let textData, let path = String(data: textData, encoding: .utf8) else {
            return nil
        }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// SAFETY: The request is built from immutable snapshots on the main thread and then only read
// across background queues / detached tasks.
struct ImagePreviewRequest: @unchecked Sendable {
    static let cacheBucketIncrement = 64

    let itemID: UUID
    let objectID: NSManagedObjectID
    let modifiedAt: Date
    let sources: [ImagePreviewSourceSnapshot]
    let requestedPixelSize: Int

    init?(
        item: ClipItem,
        requestedPixelSize: Int
    ) {
        guard item.itemTypeValue == .image else { return nil }

        let sources = (item.representations ?? [])
            .sorted(by: { $0.displayOrder < $1.displayOrder })
            .map(ImagePreviewSourceSnapshot.init(representation:))

        self.init(
            itemID: item.id,
            objectID: item.objectID,
            modifiedAt: item.modifiedAt,
            sources: sources,
            requestedPixelSize: requestedPixelSize
        )
    }

    init(
        itemID: UUID,
        objectID: NSManagedObjectID,
        modifiedAt: Date,
        sources: [ImagePreviewSourceSnapshot],
        requestedPixelSize: Int
    ) {
        self.itemID = itemID
        self.objectID = objectID
        self.modifiedAt = modifiedAt
        self.sources = sources
        self.requestedPixelSize = max(1, requestedPixelSize)
    }

    static func bucketedPixelSize(for requestedPixelSize: Int) -> Int {
        let normalizedSize = max(1, requestedPixelSize)
        let bucketIncrement = max(1, cacheBucketIncrement)
        return ((normalizedSize + bucketIncrement - 1) / bucketIncrement) * bucketIncrement
    }

    var cachePixelSize: Int {
        Self.bucketedPixelSize(for: requestedPixelSize)
    }

    var cacheKey: String {
        let version = Int64(modifiedAt.timeIntervalSince1970 * 1000)
        let sourceSignature = sources.map(\.cacheSignature).joined(separator: "|")
        return "image-preview.\(itemID.uuidString).\(version).\(cachePixelSize).\(sourceSignature)"
    }

    var hasRecoverableOriginalSource: Bool {
        sources.contains(where: \.hasRecoverablePayload)
    }

    var shouldCacheMissingResult: Bool {
        hasRecoverableOriginalSource == false
    }
}

enum ImagePreviewLoadSource: Equatable, Sendable {
    case cache
    case assetFileURL
    case fileURLRepresentation
    case inlineData
}

struct ImagePreviewLoadResult {
    let image: NSImage
    let source: ImagePreviewLoadSource
}

final class CardImagePreviewLoader {
    static let shared = CardImagePreviewLoader()

    private init() {}

    func loadPreview(for request: ImagePreviewRequest) -> ImagePreviewLoadResult? {
        if let cached = ThumbnailImageCache.shared.cachedImage(forKey: request.cacheKey) {
            return ImagePreviewLoadResult(image: cached, source: .cache)
        }

        if ThumbnailImageCache.shared.hasMissing(forKey: request.cacheKey) {
            return nil
        }

        guard let result = Self.resolvePreview(for: request) else {
            if request.shouldCacheMissingResult {
                ThumbnailImageCache.shared.setMissing(forKey: request.cacheKey)
            }
            return nil
        }

        ThumbnailImageCache.shared.setImage(
            result.image,
            forKey: request.cacheKey,
            cost: result.image.thumbnailByteCost
        )

        return result
    }

    static func resolvePreview(for request: ImagePreviewRequest) -> ImagePreviewLoadResult? {
        for source in request.sources where source.isRenderableImageKind {
            if let assetFileURL = source.assetFileURL {
                if let image = downsampleImage(at: assetFileURL, maxPixelSize: request.cachePixelSize)
                    ?? rasterizedImage(fromFileURL: assetFileURL, maxPixelSize: request.cachePixelSize)
                {
                    return ImagePreviewLoadResult(image: image, source: .assetFileURL)
                }
            }
        }

        for source in request.sources where source.kind == .fileURL {
            if let fileURL = source.fileURLRepresentation {
                if let image = downsampleImage(at: fileURL, maxPixelSize: request.cachePixelSize)
                    ?? rasterizedImage(fromFileURL: fileURL, maxPixelSize: request.cachePixelSize)
                {
                    return ImagePreviewLoadResult(image: image, source: .fileURLRepresentation)
                }
            }
        }

        for source in request.sources where source.isRenderableImageKind {
            if let binaryData = source.binaryData {
                if let image = downsampleImage(from: binaryData, maxPixelSize: request.cachePixelSize)
                    ?? rasterizedImage(fromData: binaryData, maxPixelSize: request.cachePixelSize)
                {
                    return ImagePreviewLoadResult(image: image, source: .inlineData)
                }
            }
        }

        return nil
    }
}

private func rasterizedImage(fromFileURL url: URL, maxPixelSize: Int) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    return image.scaledForPreview(maxPixelSize: maxPixelSize)
}

private func rasterizedImage(fromData data: Data, maxPixelSize: Int) -> NSImage? {
    guard let image = NSImage(data: data) else { return nil }
    return image.scaledForPreview(maxPixelSize: maxPixelSize)
}

private func downsampleImage(at url: URL, maxPixelSize: Int) -> NSImage? {
    guard
        let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        )
    else {
        return nil
    }

    return downsampleImage(from: source, maxPixelSize: maxPixelSize)
}

private func downsampleImage(from data: Data, maxPixelSize: Int) -> NSImage? {
    guard
        let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        )
    else {
        return nil
    }

    return downsampleImage(from: source, maxPixelSize: maxPixelSize)
}

private func downsampleImage(from source: CGImageSource, maxPixelSize: Int) -> NSImage? {
    guard CGImageSourceGetCount(source) > 0 else {
        return nil
    }

    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
    ]

    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }

    return NSImage(cgImage: thumbnail, size: .zero)
}

private extension NSImage {
    func scaledForPreview(maxPixelSize: Int) -> NSImage {
        let targetMax = max(1, maxPixelSize)
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = cgImage.width
            let height = cgImage.height
            let longest = max(width, height)
            guard longest > targetMax else {
                return NSImage(cgImage: cgImage, size: .zero)
            }

            let scale = CGFloat(targetMax) / CGFloat(longest)
            let targetWidth = max(1, Int((CGFloat(width) * scale).rounded()))
            let targetHeight = max(1, Int((CGFloat(height) * scale).rounded()))
            let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            guard
                let context = CGContext(
                    data: nil,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            else {
                return self
            }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

            guard let scaledCGImage = context.makeImage() else { return self }
            return NSImage(cgImage: scaledCGImage, size: .zero)
        }

        guard size.width > 0, size.height > 0 else { return self }
        let longest = max(size.width, size.height)
        guard longest > CGFloat(targetMax) else { return self }

        let scale = CGFloat(targetMax) / longest
        let targetSize = NSSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize))
        image.unlockFocus()
        return image
    }

    var thumbnailByteCost: Int {
        let bitmapRepresentations = representations.compactMap { $0 as? NSBitmapImageRep }
        if
            let bestRepresentation = bitmapRepresentations.max(
                by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }
            ),
            bestRepresentation.pixelsWide > 0,
            bestRepresentation.pixelsHigh > 0
        {
            return max(1, bestRepresentation.pixelsWide * bestRepresentation.pixelsHigh * 4)
        }

        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        return max(1, width * height * 4)
    }
}
