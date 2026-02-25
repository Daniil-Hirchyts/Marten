import CoreGraphics
import Foundation
import ImageIO
import MartenCore
import MartenIOSApp
import UIKit

enum KeyboardLinkPreviewImageResult {
    case banner(UIImage)
    case favicon(UIImage)
}

actor KeyboardLinkBannerImageLoader {
    static let shared = KeyboardLinkBannerImageLoader()

    private final class CachedResult: NSObject {
        let result: KeyboardLinkPreviewImageResult

        init(_ result: KeyboardLinkPreviewImageResult) {
            self.result = result
        }
    }

    private let memoryCache = NSCache<NSString, CachedResult>()
    private var inFlight: [String: Task<KeyboardLinkPreviewImageResult?, Never>] = [:]
    private let cacheDirectoryURL: URL?

    init() {
        memoryCache.countLimit = 120

        let fileManager = FileManager.default
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = cachesDirectory.appendingPathComponent(
                "MartenKeyboardLinkPreviews",
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            cacheDirectoryURL = directory
        } else {
            cacheDirectoryURL = nil
        }
    }

    func loadImage(
        for item: SharedClipItemSummary,
        allowsNetworkFetch: Bool,
        maxPixelSize: CGFloat = 1_200,
        faviconMaxPixelSize: CGFloat = 256
    ) async -> KeyboardLinkPreviewImageResult? {
        guard item.itemType == .url, let linkPreview = item.linkPreview else { return nil }

        let cacheKey = "kb-link-\(linkPreview.id.uuidString)-\(Int64(linkPreview.fetchedAt.timeIntervalSince1970 * 1000))"

        if let cached = memoryCache.object(forKey: cacheKey as NSString)?.result {
            return cached
        }

        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        let localPath = normalizedPath(linkPreview.imagePath)
        let remoteURL = normalizedURL(linkPreview.imageURL)
        let linkURL = normalizedWebURL(item.insertionText)
        let cacheURL = cachedBannerFileURL(for: linkPreview.id)

        let task = Task<KeyboardLinkPreviewImageResult?, Never> {
            if let localPath,
               let diskImage = await Self.loadDownsampledImage(atPath: localPath, maxPixelSize: maxPixelSize) {
                return .banner(diskImage)
            }

            if let cacheURL,
               let cachedImage = await Self.loadDownsampledImage(
                   atPath: cacheURL.path,
                   maxPixelSize: maxPixelSize
               ) {
                return .banner(cachedImage)
            }

            if allowsNetworkFetch,
               let remoteURL,
               let data = await Self.fetchImageData(from: remoteURL) {
                if let cacheURL {
                    try? data.write(to: cacheURL, options: [.atomic])
                    if let image = await Self.loadDownsampledImage(
                        atPath: cacheURL.path,
                        maxPixelSize: maxPixelSize
                    ) {
                        return .banner(image)
                    }
                }

                if let image = await Self.downsampledImage(from: data, maxPixelSize: maxPixelSize) {
                    return .banner(image)
                }
            }

            if allowsNetworkFetch,
               let favicon = await Self.loadFaviconImage(
                   for: linkURL,
                   maxPixelSize: faviconMaxPixelSize
               ) {
                return .favicon(favicon)
            }

            return nil
        }

        inFlight[cacheKey] = task
        let result = await task.value
        inFlight[cacheKey] = nil

        if let result {
            memoryCache.setObject(CachedResult(result), forKey: cacheKey as NSString)
        }

        return result
    }

    private func cachedBannerFileURL(for previewID: UUID) -> URL? {
        cacheDirectoryURL?
            .appendingPathComponent("link-banner-\(previewID.uuidString)")
            .appendingPathExtension("cache")
    }

    private func normalizedPath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    private func normalizedURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private func normalizedWebURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(raw)")
    }

    private static func fetchImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        return data
    }

    private static func loadFaviconImage(for url: URL?, maxPixelSize: CGFloat) async -> UIImage? {
        guard let url, let host = url.host else { return nil }
        let scheme = url.scheme ?? "https"
        let hostWithPort = url.port.map { "\(host):\($0)" } ?? host

        let candidates = [
            URL(string: "\(scheme)://\(hostWithPort)/apple-touch-icon.png"),
            URL(string: "\(scheme)://\(hostWithPort)/favicon.ico"),
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            guard let data = await fetchImageData(from: candidate) else { continue }
            if let image = await downsampledImage(from: data, maxPixelSize: maxPixelSize) {
                return image
            }
        }

        return nil
    }

    private static func downsampledImage(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: createThumbnailImage(
                        source: source,
                        maxPixelSize: maxPixelSize
                    )
                )
            }
        }
    }

    private static func loadDownsampledImage(atPath path: String, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: createThumbnailImage(
                        source: source,
                        maxPixelSize: maxPixelSize
                    )
                )
            }
        }
    }

    private static func createThumbnailImage(
        source: CGImageSource,
        maxPixelSize: CGFloat
    ) -> UIImage? {
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
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
