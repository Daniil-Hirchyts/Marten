import CoreData
import Foundation
import MartenCore
import UIKit
import os.log

enum LinkPreviewImageResult {
    case banner(UIImage)
    case favicon(UIImage)
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

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached.result
        }

        // 2. Deduplicate in-flight requests
        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        // Capture values before entering the task to avoid Core Data threading issues
        let imagePath = linkPreview.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = linkPreview.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewObjectID = linkPreview.managedObjectContext != nil ? linkPreview.objectID : nil
        let linkURLString = linkPreview.url.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = Task<LinkPreviewImageResult?, Never> {
            // 3. Try loading from disk
            if let path = imagePath, !path.isEmpty,
               let diskImage = await Self.loadImageFromDisk(path: path) {
                return .banner(diskImage)
            }

            // 4. Fall back to downloading from imageURL
            if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                if let (image, data) = await Self.downloadImage(from: url) {
                    // Persist to disk so we don't re-download next time
                    await Self.persistDownloadedImage(data: data, previewObjectID: previewObjectID)
                    return .banner(image)
                }
            }

            // 5. Try favicon as fallback
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

    // MARK: - Private helpers

    private func cacheKey(for linkPreview: LinkPreview) -> String {
        let version = Int64(linkPreview.fetchedAt.timeIntervalSince1970 * 1000)
        return "lp-\(linkPreview.id.uuidString)-\(version)"
    }

    private static func loadImageFromDisk(path: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: UIImage(contentsOfFile: path))
            }
        }
    }

    /// Downloads the image and returns both the UIImage and the raw Data for disk persistence.
    private static func downloadImage(from url: URL) async -> (UIImage, Data)? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }

        return (image, data)
    }

    /// Attempts to load a favicon from the website's root domain.
    private static func loadFavicon(from urlString: String?) async -> UIImage? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        let scheme = url.scheme ?? "https"

        // Try apple-touch-icon first (higher resolution, ~180x180)
        if let touchIconURL = URL(string: "\(scheme)://\(host)/apple-touch-icon.png"),
           let (image, _) = await downloadImage(from: touchIconURL) {
            return image
        }

        // Fall back to favicon.ico
        if let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico"),
           let (image, _) = await downloadImage(from: faviconURL) {
            return image
        }

        return nil
    }

    /// Saves the downloaded image to the AssetStore and updates the LinkPreview's imagePath.
    private static func persistDownloadedImage(data: Data, previewObjectID: NSManagedObjectID?) {
        guard let objectID = previewObjectID else { return }

        // Run on a background queue to avoid blocking the main actor
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
