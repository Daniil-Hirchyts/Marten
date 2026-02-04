import CoreData
import Foundation

final class AssetManagementService {
    private let persistence: PersistenceController
    private let assetStore: AssetStore

    init(
        persistence: PersistenceController = .shared,
        assetStore: AssetStore = .shared
    ) {
        self.persistence = persistence
        self.assetStore = assetStore
    }

    func updateThumbnail(
        objectID: NSManagedObjectID,
        data: Data,
        fileExtension: String = "png"
    ) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            if let existingPath = item.thumbnailPath {
                try? FileManager.default.removeItem(atPath: existingPath)
            }

            let assetRef = try assetStore.store(data: data, fileExtension: fileExtension)
            let url = assetStore.urlForAsset(assetRef, fileExtension: fileExtension)
            item.thumbnailPath = url.path
            try context.save()
        }

        try refreshItemInViewContext(objectID)
    }

    func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            if let existing = item.linkPreview {
                if let existingImagePath = existing.imagePath {
                    try? FileManager.default.removeItem(atPath: existingImagePath)
                }
                context.delete(existing)
            }

            guard
                let preview = NSEntityDescription.insertNewObject(
                    forEntityName: "LinkPreview",
                    into: context
                ) as? LinkPreview
            else {
                throw ClipItemStoreError.creationFailed
            }

            preview.id = UUID()
            preview.url = payload.url.absoluteString
            preview.title = payload.title
            preview.siteName = payload.siteName
            preview.summary = payload.summary
            preview.fetchedAt = payload.fetchedAt
            preview.fetchFailed = false

            if let imageData = payload.imageData {
                let assetRef = try assetStore.store(data: imageData, fileExtension: "png")
                let url = assetStore.urlForAsset(assetRef, fileExtension: "png")
                preview.imagePath = url.path
            }

            preview.clipItem = item
            item.linkPreview = preview
            item.needsLinkPreview = false
            try context.save()
        }

        try refreshItemInViewContext(objectID)
    }

    func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            if let representations = item.representations {
                for rep in representations {
                    if rep.kindValue == .png || rep.kindValue == .jpeg || rep.kindValue == .tiff {
                        rep.binaryData = imageData
                        rep.byteCount = Int64(imageData.count)
                    }
                }
            }

            if let existingPath = item.thumbnailPath {
                try? FileManager.default.removeItem(atPath: existingPath)
            }

            let assetRef = try assetStore.store(data: imageData, fileExtension: "png")
            let url = assetStore.urlForAsset(assetRef, fileExtension: "png")
            item.thumbnailPath = url.path

            let now = Date()
            item.byteCount = Int64(imageData.count)
            item.modifiedAt = now
            item.displayOrder = currentDisplayOrder(reference: now)

            try context.save()
        }

        try refreshItemInViewContext(objectID)
    }

    func markLinkPreviewFetchFailed(
        objectID: NSManagedObjectID,
        url: URL,
        fetchedAt: Date = Date()
    ) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            let preview: LinkPreview
            if let existing = item.linkPreview {
                preview = existing
            } else {
                guard
                    let created = NSEntityDescription.insertNewObject(
                        forEntityName: "LinkPreview",
                        into: context
                    ) as? LinkPreview
                else {
                    throw ClipItemStoreError.creationFailed
                }

                created.id = UUID()
                created.clipItem = item
                item.linkPreview = created
                preview = created
            }

            preview.url = url.absoluteString
            preview.fetchedAt = fetchedAt
            preview.fetchFailed = true
            item.needsLinkPreview = false
            try context.save()
        }

        try refreshItemInViewContext(objectID)
    }

    func fetchPendingLinkPreviewTargets(limit: Int = 25) throws -> [(
        objectID: NSManagedObjectID,
        url: URL
    )] {
        let context = persistence.newBackgroundContext()
        var results: [(NSManagedObjectID, URL)] = []

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(
                format: "needsLinkPreview == YES AND linkPreview == nil"
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            request.fetchLimit = limit

            let items = try context.fetch(request)
            for item in items {
                guard
                    item.itemTypeValue == .url,
                    let text = item.primaryText,
                    let url = URL(string: text)
                else {
                    continue
                }

                results.append((item.objectID, url))
            }
        }

        return results
    }

    func removeAssets(for item: ClipItem) {
        for representation in item.representations ?? [] {
            guard let assetRef = representation.assetRef else { continue }
            try? assetStore.delete(assetRef: assetRef, fileExtension: representation.fileExtension)
        }

        if let thumbnailPath = item.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbnailPath)
        }

        if let previewImagePath = item.linkPreview?.imagePath {
            try? FileManager.default.removeItem(atPath: previewImagePath)
        }
    }

    private func refreshItemInViewContext(_ objectID: NSManagedObjectID) throws {
        let viewContext = persistence.viewContext

        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    private func currentDisplayOrder(reference: Date = Date()) -> Int64 {
        Int64(reference.timeIntervalSince1970 * 1000)
    }
}

// SAFETY: AssetManagementService is immutable after initialization. All Core Data work is executed
// on the owning context queue via `performAndWaitThrowing`, and file operations are delegated to
// `AssetStore`/`FileManager`.
extension AssetManagementService: @unchecked Sendable {}

extension AssetManagementService: AssetManagementServicing {}
