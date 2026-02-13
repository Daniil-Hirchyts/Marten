import CoreData
import Foundation
import MartenCore
import UIKit
import os.log

private let logger = Logger(subsystem: "com.hirchyts.marten", category: "LinkPreviewImageLoader")

@MainActor
final class LinkPreviewImageLoader {
    static let shared = LinkPreviewImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 200
    }

    func loadImage(for linkPreview: LinkPreview) async -> UIImage? {
        let cacheKey = cacheKey(for: linkPreview)

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // 2. Deduplicate in-flight requests
        if let runningTask = inFlight[cacheKey] {
            return await runningTask.value
        }

        // Capture values before entering the task to avoid Core Data threading issues
        let imagePath = linkPreview.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = linkPreview.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewObjectID = linkPreview.managedObjectContext != nil ? linkPreview.objectID : nil

        let task = Task<UIImage?, Never> {
            // 3. Try loading from disk
            if let path = imagePath, !path.isEmpty,
               let diskImage = await Self.loadImageFromDisk(path: path) {
                return diskImage
            }

            // 4. Fall back to downloading from imageURL
            if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                if let (image, data) = await Self.downloadImage(from: url) {
                    // Persist to disk so we don't re-download next time
                    await Self.persistDownloadedImage(data: data, previewObjectID: previewObjectID)
                    return image
                }
            }

            return nil
        }

        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil

        if let image {
            memoryCache.setObject(image, forKey: cacheKey as NSString)
        }

        return image
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
