import AppKit
import Foundation
import LinkPresentation

public struct LinkPreviewPayload: Codable, Sendable {
    public let url: URL
    public let title: String?
    public let siteName: String?
    public let summary: String?
    public let imageData: Data?
    public let iconData: Data?
    public let fetchedAt: Date

    public init(
        url: URL,
        title: String?,
        siteName: String?,
        summary: String?,
        imageData: Data?,
        iconData: Data?,
        fetchedAt: Date
    ) {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.summary = summary
        self.imageData = imageData
        self.iconData = iconData
        self.fetchedAt = fetchedAt
    }
}

public enum LinkPreviewError: Error, LocalizedError {
    case disabled
    case invalidURL
    case fetchFailed(Error)
    case noMetadata

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
        }
    }
}

public final class LinkPreviewFetcher {
    private let userDefaults: UserDefaults
    private let userDefaultsKey = "generateLinkPreviews"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: userDefaultsKey)
        }
        set {
            userDefaults.set(newValue, forKey: userDefaultsKey)
        }
    }

    public func fetchPreview(for url: URL) async throws -> LinkPreviewPayload {
        guard isEnabled else {
            throw LinkPreviewError.disabled
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LinkPreviewError.invalidURL
        }

        let provider = LPMetadataProvider()

        let metadata: LPLinkMetadata
        do {
            metadata = try await provider.startFetchingMetadata(for: url)
        } catch {
            throw LinkPreviewError.fetchFailed(error)
        }

        let imageData: Data?
        if let imageProvider = metadata.imageProvider {
            imageData = try? await loadImage(from: imageProvider)
        } else {
            imageData = nil
        }

        let iconData: Data?
        if let iconProvider = metadata.iconProvider {
            iconData = try? await loadImage(from: iconProvider)
        } else {
            iconData = nil
        }

        let title = metadata.title
        let siteName = metadata.url?.host ?? metadata.originalURL?.host
        let summary: String? = nil

        if title == nil && siteName == nil && imageData == nil && iconData == nil {
            throw LinkPreviewError.noMetadata
        }

        return LinkPreviewPayload(
            url: url,
            title: title,
            siteName: siteName,
            summary: summary,
            imageData: imageData,
            iconData: iconData,
            fetchedAt: Date()
        )
    }

    private func loadImage(from provider: NSItemProvider) async throws -> Data? {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? NSImage else {
                    continuation.resume(throwing: LinkPreviewError.noMetadata)
                    return
                }
                continuation.resume(returning: image)
            }
        }

        guard let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

extension LinkPreviewFetcher: @unchecked Sendable {}
