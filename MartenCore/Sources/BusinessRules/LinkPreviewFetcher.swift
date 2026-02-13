import Foundation
import LinkPresentation
import os.log
#if canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#endif

private let logger = Logger(subsystem: "com.hirchyts.marten", category: "LinkPreviewFetcher")

public struct LinkPreviewPayload: Codable, Sendable {
    public let url: URL
    public let title: String?
    public let siteName: String?
    public let summary: String?
    public let imageData: Data?
    public let imageURL: String?
    public let fetchedAt: Date

    public init(
        url: URL,
        title: String?,
        siteName: String?,
        summary: String?,
        imageData: Data?,
        imageURL: String?,
        fetchedAt: Date
    ) {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.summary = summary
        self.imageData = imageData
        self.imageURL = imageURL
        self.fetchedAt = fetchedAt
    }
}

public enum LinkPreviewError: Error, LocalizedError {
    case disabled
    case invalidURL
    case fetchFailed(Error)
    case noMetadata
    case timeout

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Link previews are disabled."
        case .invalidURL:
            return "Invalid URL for link preview."
        case .fetchFailed(let error):
            return "Failed to fetch link preview metadata: \(error.localizedDescription)"
        case .noMetadata:
            return "No metadata available for this URL."
        case .timeout:
            return "Link preview fetch timed out."
        }
    }
}

// MARK: - LinkPreviewFetcher

public final class LinkPreviewFetcher {
    private static let lpFetchTimeoutSeconds: TimeInterval = 15
    private static let ogFetchTimeoutSeconds: TimeInterval = 10
    private static let imageDownloadTimeoutSeconds: TimeInterval = 10
    /// Maximum bytes to read when parsing HTML for OG tags (only the <head> matters).
    private static let ogHTMLByteLimit = 51_200 // 50 KB

    private let userDefaults: UserDefaults
    private let userDefaultsKey = "generateLinkPreviews"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var isEnabled: Bool {
        get { userDefaults.bool(forKey: userDefaultsKey) }
        set { userDefaults.set(newValue, forKey: userDefaultsKey) }
    }

    // MARK: - Public API

    public func fetchPreview(for url: URL) async throws -> LinkPreviewPayload {
        guard isEnabled else { throw LinkPreviewError.disabled }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LinkPreviewError.invalidURL
        }

        // Strategy: try LPMetadataProvider first. If it fails or returns no image,
        // fall back to lightweight Open Graph HTML parsing.
        if let lpResult = await tryLPMetadataProvider(for: url) {
            logger.debug("LPMetadataProvider succeeded for \(url.absoluteString, privacy: .public)")
            return lpResult
        }

        logger.info("LPMetadataProvider failed or had no image, trying OG fallback for \(url.absoluteString, privacy: .public)")

        if let ogResult = await tryOpenGraphFallback(for: url) {
            logger.debug("OG fallback succeeded for \(url.absoluteString, privacy: .public)")
            return ogResult
        }

        logger.warning("Both LP and OG failed for \(url.absoluteString, privacy: .public)")
        throw LinkPreviewError.noMetadata
    }

    // MARK: - LPMetadataProvider path

    private func tryLPMetadataProvider(for url: URL) async -> LinkPreviewPayload? {
        do {
            let metadata = try await withTimeout(seconds: Self.lpFetchTimeoutSeconds) {
                let provider = LPMetadataProvider()
                return try await provider.startFetchingMetadata(for: url)
            }

            var imageData: Data?
            if let imageProvider = metadata.imageProvider {
                imageData = try? await withTimeout(seconds: Self.imageDownloadTimeoutSeconds) {
                    try await self.loadImage(from: imageProvider)
                }
            }

            let title = metadata.title
            let siteName = metadata.url?.host ?? metadata.originalURL?.host

            // If we got nothing useful, let the OG fallback try
            if title == nil && siteName == nil && imageData == nil {
                return nil
            }

            return LinkPreviewPayload(
                url: url,
                title: title,
                siteName: siteName,
                summary: nil,
                imageData: imageData,
                imageURL: nil, // LPMetadataProvider doesn't expose the direct image URL
                fetchedAt: Date()
            )
        } catch {
            logger.info("LPMetadataProvider error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Open Graph HTML fallback

    private func tryOpenGraphFallback(for url: URL) async -> LinkPreviewPayload? {
        do {
            let ogTags = try await fetchOpenGraphTags(for: url)

            let title = ogTags["og:title"]
            let siteName = ogTags["og:site_name"] ?? url.host
            let ogImageURLString = ogTags["og:image"]
            let description = ogTags["og:description"]

            // Resolve the image URL (it may be relative)
            let resolvedImageURL: URL? = {
                guard let raw = ogImageURLString, !raw.isEmpty else { return nil }
                if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
                return URL(string: raw, relativeTo: url)?.absoluteURL
            }()

            // Download the image if we have a URL
            var imageData: Data?
            if let imageURL = resolvedImageURL {
                imageData = await downloadImageData(from: imageURL)
            }

            // Need at least a title or image to be useful
            if title == nil && imageData == nil {
                return nil
            }

            return LinkPreviewPayload(
                url: url,
                title: title,
                siteName: siteName,
                summary: description,
                imageData: imageData,
                imageURL: resolvedImageURL?.absoluteString,
                fetchedAt: Date()
            )
        } catch {
            logger.info("OG fallback error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Fetches the HTML `<head>` and parses Open Graph meta tags.
    private func fetchOpenGraphTags(for url: URL) async throws -> [String: String] {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.ogFetchTimeoutSeconds
        request.setValue(
            "Mozilla/5.0 (compatible; Marten/1.0)",
            forHTTPHeaderField: "User-Agent"
        )
        // Only need the head section
        request.cachePolicy = .returnCacheDataElseLoad

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LinkPreviewError.fetchFailed(
                NSError(domain: "OGFetch", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP error"
                ])
            )
        }

        // Limit how much HTML we parse
        let limitedData = data.prefix(Self.ogHTMLByteLimit)
        guard let html = String(data: limitedData, encoding: .utf8)
                ?? String(data: limitedData, encoding: .isoLatin1) else {
            throw LinkPreviewError.noMetadata
        }

        return parseOpenGraphTags(from: html)
    }

    /// Simple parser for `<meta property="og:..." content="...">` tags.
    /// Handles both single-quoted and double-quoted attributes, and the `/>` or `>` closing.
    private func parseOpenGraphTags(from html: String) -> [String: String] {
        var tags: [String: String] = [:]

        // Pattern: <meta ... property="og:XXX" ... content="YYY" ...>
        let propertyFirst = try? NSRegularExpression(
            pattern: "<meta\\s[^>]*?(?:property|name)\\s*=\\s*[\"'](?<prop>og:[^\"']+)[\"'][^>]*?content\\s*=\\s*[\"'](?<val>[^\"']*)[\"'][^>]*?\\/?>",
            options: .caseInsensitive
        )

        // Also try content before property (some sites reverse the order)
        let contentFirst = try? NSRegularExpression(
            pattern: "<meta\\s[^>]*?content\\s*=\\s*[\"'](?<val>[^\"']*)[\"'][^>]*?(?:property|name)\\s*=\\s*[\"'](?<prop>og:[^\"']+)[\"'][^>]*?\\/?>",
            options: .caseInsensitive
        )

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)

        for regex in [propertyFirst, contentFirst].compactMap({ $0 }) {
            let matches = regex.matches(in: html, range: fullRange)
            for match in matches {
                guard let propRange = Range(match.range(withName: "prop"), in: html),
                      let valRange = Range(match.range(withName: "val"), in: html) else {
                    continue
                }
                let prop = String(html[propRange])
                let val = String(html[valRange])
                if !val.isEmpty && tags[prop] == nil {
                    tags[prop] = decodeHTMLEntities(val)
                }
            }
        }

        return tags
    }

    private func decodeHTMLEntities(_ string: String) -> String {
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

    // MARK: - Image loading

    private func downloadImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.imageDownloadTimeoutSeconds
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              !data.isEmpty else {
            return nil
        }

        // Validate it's actually an image
        #if canImport(UIKit)
        guard UIImage(data: data) != nil else { return nil }
        #elseif canImport(AppKit)
        guard NSImage(data: data) != nil else { return nil }
        #endif

        return data
    }

    private func loadImage(from provider: NSItemProvider) async throws -> Data? {
        let image: PlatformImage = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: PlatformImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? PlatformImage else {
                    continuation.resume(throwing: LinkPreviewError.noMetadata)
                    return
                }
                continuation.resume(returning: image)
            }
        }
        return pngData(from: image)
    }

    private func pngData(from image: PlatformImage) -> Data? {
        #if canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        return image.pngData()
        #else
        return nil
        #endif
    }

    // MARK: - Timeout utility

    /// Runs `body` with a timeout. The real result always takes priority over the timeout.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: Result<T, Error>.self) { group in
            // The real work
            group.addTask {
                do {
                    let value = try await body()
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            }

            // The timeout sentinel
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .failure(LinkPreviewError.timeout)
            }

            // Collect the first result. If it's the real task, use it.
            // If it's the timeout, check if the real task has also completed.
            var realResult: Result<T, Error>?
            var gotTimeout = false

            for try await result in group {
                switch result {
                case .success:
                    group.cancelAll()
                    return try result.get()
                case .failure(let error):
                    if error is LinkPreviewError, case .timeout = error as? LinkPreviewError {
                        gotTimeout = true
                    } else {
                        realResult = result
                    }
                }
            }

            // If we have a real result (even if it's an error), prefer it over timeout
            if let realResult {
                group.cancelAll()
                return try realResult.get()
            }

            if gotTimeout {
                throw LinkPreviewError.timeout
            }

            throw LinkPreviewError.noMetadata
        }
    }
}

// SAFETY: LinkPreviewFetcher stores preferences in UserDefaults (thread-safe) and performs all
// fetch operations using local variables.
extension LinkPreviewFetcher: @unchecked Sendable {}
