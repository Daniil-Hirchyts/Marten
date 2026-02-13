import CoreGraphics
import Foundation
import ImageIO
import MartenCore
import MartenIOSApp
import UIKit

actor KeyboardImagePreviewLoader {
    static let shared = KeyboardImagePreviewLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        memoryCache.countLimit = 120
    }

    func loadThumbnail(
        for item: SharedClipItemSummary,
        maxPixelSize: CGFloat = 900
    ) async -> UIImage? {
        guard item.itemType == .image else { return nil }
        guard let path = normalizedPath(item.thumbnailPath) else { return nil }

        let cacheKey = "kb-image-\(item.id.uuidString)-\(Int64(item.modifiedAt.timeIntervalSince1970 * 1000))-\(path)"
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        let task = Task<UIImage?, Never> {
            await Self.loadDownsampledImage(atPath: path, maxPixelSize: maxPixelSize)
        }

        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil

        if let image {
            memoryCache.setObject(image, forKey: cacheKey as NSString)
        }

        return image
    }

    private func normalizedPath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    private static func loadDownsampledImage(atPath path: String, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
                ]

                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: UIImage(cgImage: cgImage))
            }
        }
    }
}
