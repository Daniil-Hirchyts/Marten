import AppKit
import CoreData
import Foundation
import LinkPresentation
import MartenCore
import os.log

public enum LinkPreviewImageResult {
    case banner(NSImage)
    case favicon(NSImage)
}

private let logger = Logger(subsystem: "com.hirchyts.marten", category: "LinkPreviewImageLoader")

@MainActor
final class LinkPreviewImageLoader {
    static let shared = LinkPreviewImageLoader()

    private final class CachedResult: NSObject {
        let result: LinkPreviewImageResult
        init(_ result: LinkPreviewImageResult) { self.result = result }
    }

    private let memoryCache = NSCache<NSString, CachedResult>()
    private var inFlight: [String: Task<LinkPreviewImageResult?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 200
    }

    func loadImage(for linkPreview: LinkPreview) async -> LinkPreviewImageResult? {
        let cacheKey = cacheKey(for: linkPreview)

        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached.result
        }

        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        let imagePath = linkPreview.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = linkPreview.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewObjectID = linkPreview.managedObjectContext != nil ? linkPreview.objectID : nil
        let linkURLString = linkPreview.url.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = Task<LinkPreviewImageResult?, Never> {
            // 1. Try loading from local disk
            if let path = imagePath, !path.isEmpty,
               let diskImage = await Self.loadImageFromDisk(path: path) {
                return .banner(diskImage)
            }

            // 2. Try downloading from the stored image URL
            if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                if let (image, data) = await Self.downloadImage(from: url) {
                    Self.persistDownloadedImage(data: data, previewObjectID: previewObjectID)
                    return .banner(image)
                }
            }

            // 3. No local image and no stored image URL (e.g. synced from another device).
            //    Use LPMetadataProvider to fetch the banner image natively.
            if let lpImage = await Self.fetchViaLPMetadata(from: linkURLString, previewObjectID: previewObjectID) {
                return .banner(lpImage)
            }

            // 4. OG parsing fallback (lighter weight than LP, handles simpler pages)
            if let ogImage = await Self.fetchOGImage(from: linkURLString, previewObjectID: previewObjectID) {
                return .banner(ogImage)
            }

            // 5. Favicon fallback
            if let faviconImage = await Self.loadFavicon(from: linkURLString) {
                return .favicon(faviconImage)
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

    /// Load a favicon directly from a raw URL string (when no LinkPreview entity exists).
    func loadFaviconOnly(urlString: String) async -> LinkPreviewImageResult? {
        let cacheKey = "favicon-\(urlString)"

        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached.result
        }

        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        let task = Task<LinkPreviewImageResult?, Never> {
            // Try LP metadata first for a proper banner
            if let lpImage = await Self.fetchViaLPMetadata(from: urlString, previewObjectID: nil) {
                return .banner(lpImage)
            }

            // Then OG parsing
            if let ogImage = await Self.fetchOGImage(from: urlString, previewObjectID: nil) {
                return .banner(ogImage)
            }

            // Finally favicon
            if let faviconImage = await Self.loadFavicon(from: urlString) {
                return .favicon(faviconImage)
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

    // MARK: - Private helpers

    private func cacheKey(for linkPreview: LinkPreview) -> String {
        let version = Int64(linkPreview.fetchedAt.timeIntervalSince1970 * 1000)
        return "lp-\(linkPreview.id.uuidString)-\(version)"
    }

    private static func loadImageFromDisk(path: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: NSImage(contentsOfFile: path))
            }
        }
    }

    private static func downloadImage(from url: URL) async -> (NSImage, Data)? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = NSImage(data: data) else {
            return nil
        }

        return (image, data)
    }

    // MARK: - LPMetadataProvider

    /// Uses the native LPMetadataProvider to fetch the banner image for a URL.
    private static func fetchViaLPMetadata(from urlString: String, previewObjectID: NSManagedObjectID?) async -> NSImage? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }

        do {
            let provider = LPMetadataProvider()
            provider.timeout = 10

            let metadata = try await provider.startFetchingMetadata(for: url)

            guard let imageProvider = metadata.imageProvider else {
                logger.debug("LPMetadata: no image provider for \(urlString, privacy: .public)")
                return nil
            }

            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                imageProvider.loadObject(ofClass: NSImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let nsImage = object as? NSImage else {
                        continuation.resume(throwing: NSError(domain: "LinkPreviewImageLoader", code: -1))
                        return
                    }
                    continuation.resume(returning: nsImage)
                }
            }

            // Persist the image data so we don't re-fetch next time
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                persistDownloadedImage(data: pngData, previewObjectID: previewObjectID)
            }

            return image
        } catch {
            logger.debug("LPMetadata failed for \(urlString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - OG Image fallback

    /// Fetches the page HTML, extracts the og:image URL, and downloads the banner image.
    private static func fetchOGImage(from urlString: String, previewObjectID: NSManagedObjectID?) async -> NSImage? {
        guard !urlString.isEmpty, let pageURL = URL(string: urlString) else { return nil }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 10
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            logger.debug("OG fetch: HTML download failed for \(urlString, privacy: .public)")
            return nil
        }

        let limited = data.prefix(51_200)
        guard let html = String(data: limited, encoding: .utf8)
                ?? String(data: limited, encoding: .isoLatin1) else {
            return nil
        }

        guard let ogImageRaw = parseOGImageURL(from: html) else {
            logger.debug("OG fetch: no og:image found for \(urlString, privacy: .public)")
            return nil
        }

        let decoded = decodeHTMLEntities(ogImageRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve relative URLs
        let resolvedURL: URL? = {
            if let absolute = URL(string: decoded), absolute.scheme != nil { return absolute }
            return URL(string: decoded, relativeTo: pageURL)?.absoluteURL
        }()

        guard let imageURL = resolvedURL else {
            logger.debug("OG fetch: invalid og:image URL '\(decoded, privacy: .public)'")
            return nil
        }

        guard let (image, imageData) = await downloadImage(from: imageURL) else {
            logger.debug("OG fetch: image download failed for \(imageURL.absoluteString, privacy: .public)")
            return nil
        }

        persistDownloadedImage(data: imageData, previewObjectID: previewObjectID)

        return image
    }

    /// Lightweight og:image parser — handles both attribute orderings.
    private static func parseOGImageURL(from html: String) -> String? {
        // property before content
        let pattern1 = "<meta\\s[^>]*?(?:property|name)\\s*=\\s*[\"']og:image[\"'][^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?/?>"
        // content before property
        let pattern2 = "<meta\\s[^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?(?:property|name)\\s*=\\s*[\"']og:image[\"'][^>]*?/?>"

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)

        for pattern in [pattern1, pattern2] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: fullRange),
               let range = Range(match.range(at: 1), in: html) {
                let value = String(html[range])
                if !value.isEmpty { return value }
            }
        }

        return nil
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    // MARK: - Favicon

    private static func loadFavicon(from urlString: String?) async -> NSImage? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        let scheme = url.scheme ?? "https"

        if let touchIconURL = URL(string: "\(scheme)://\(host)/apple-touch-icon.png"),
           let (image, _) = await downloadImage(from: touchIconURL) {
            return image
        }

        if let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico"),
           let (image, _) = await downloadImage(from: faviconURL) {
            return image
        }

        return nil
    }

    // MARK: - Persistence

    private static func persistDownloadedImage(data: Data, previewObjectID: NSManagedObjectID?) {
        guard let objectID = previewObjectID else { return }

        DispatchQueue.global(qos: .utility).async {
            do {
                let assetStore = AssetStore.shared
                let assetRef = try assetStore.store(data: data, fileExtension: "png")
                let fileURL = assetStore.urlForAsset(assetRef, fileExtension: "png")

                let context = PersistenceController.shared.newBackgroundContext()
                try context.performAndWaitThrowing {
                    guard let preview = try context.existingObject(with: objectID) as? LinkPreview else {
                        return
                    }
                    preview.imagePath = fileURL.path
                    try context.save()
                }

                logger.debug("Persisted downloaded image to disk for preview \(objectID)")
            } catch {
                logger.warning("Failed to persist downloaded image: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
