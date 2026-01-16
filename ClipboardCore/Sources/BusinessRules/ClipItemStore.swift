import CoreData
import Foundation

public struct SourceAppInfo: Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum ClipItemStoreError: Error {
    case creationFailed
    case missingItem
    case missingContent
}

public final class ClipItemStore {
    private let persistence: PersistenceController
    private let assetStore: AssetStore
    private let assetThresholdBytes = 256 * 1024

    public init(persistence: PersistenceController = .shared, assetStore: AssetStore = .shared) {
        self.persistence = persistence
        self.assetStore = assetStore
    }

    @discardableResult
    public func createTextItem(
        text: String,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        let trimmedText = String(text.prefix(10_000))
        let payload = ClipItemPayload(
            representations: [ClipRepresentationPayload.plainText(trimmedText)],
            primaryText: trimmedText,
            itemType: .text
        )

        return try createItem(payload: payload, sourceApp: sourceApp, isUserCreated: isUserCreated)
    }

    @discardableResult
    public func createItem(
        payload: ClipItemPayload,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        guard !payload.representations.isEmpty else {
            throw ClipItemStoreError.missingContent
        }

        let now = Date()
        let displayOrder = currentDisplayOrder(reference: now)
        let hash = try computeContentHash(
            primaryText: payload.primaryText, representations: payload.representations)

        let context = persistence.newBackgroundContext()
        var createdObjectID: NSManagedObjectID?
        try context.performAndWaitThrowing {
            if let existing = try fetchExistingItem(hash: hash, in: context) {
                existing.modifiedAt = now
                existing.displayOrder = displayOrder
                try context.save()
                createdObjectID = existing.objectID
                return
            }

            guard
                let item = NSEntityDescription.insertNewObject(
                    forEntityName: "ClipItem", into: context) as? ClipItem
            else {
                throw ClipItemStoreError.creationFailed
            }
            item.id = UUID()
            item.createdAt = now
            item.modifiedAt = now
            item.displayOrder = displayOrder
            item.sourceAppBundleID = sourceApp?.bundleID
            item.sourceAppName = sourceApp?.name
            item.itemTypeValue = payload.itemType
            item.primaryText = payload.primaryText
            item.searchableText = deriveSearchableText(
                primaryText: payload.primaryText, representations: payload.representations)
            item.contentHash = hash
            item.needsLinkPreview = payload.needsLinkPreview
            item.isSensitive = payload.isSensitive
            item.isTransient = payload.isTransient
            item.isUserCreated = isUserCreated

            var totalBytes: Int64 = 0
            let sortedRepresentations = payload.representations.sorted {
                $0.displayOrder < $1.displayOrder
            }

            for repPayload in sortedRepresentations {
                guard
                    let representation = NSEntityDescription.insertNewObject(
                        forEntityName: "ClipRepresentation",
                        into: context
                    ) as? ClipRepresentation
                else {
                    throw ClipItemStoreError.creationFailed
                }
                representation.id = UUID()
                representation.uti = repPayload.uti
                representation.kindValue = repPayload.kind
                representation.displayOrder = repPayload.displayOrder
                representation.fileExtension = repPayload.fileExtension
                representation.clipItem = item

                var repBytes: Int64 = 0
                if let text = repPayload.text, !text.isEmpty {
                    let textData = Data(text.utf8)
                    representation.textData = textData
                    repBytes += Int64(textData.count)
                }

                if let data = repPayload.data {
                    repBytes += Int64(data.count)
                    if data.count > assetThresholdBytes {
                        representation.assetRef = try assetStore.store(
                            data: data, fileExtension: repPayload.fileExtension)
                    } else {
                        representation.binaryData = data
                    }
                }

                representation.byteCount = repBytes
                totalBytes += repBytes
                item.addToRepresentations(representation)
            }

            item.byteCount = totalBytes

            let clipboardPinboard = try fetchOrCreateSystemClipboardPinboard(in: context)
            item.addToPinboards(clipboardPinboard)

            try context.save()
            createdObjectID = item.objectID
        }

        guard let objectID = createdObjectID else {
            throw ClipItemStoreError.creationFailed
        }

        let viewContext = persistence.viewContext
        var fetchedItem: ClipItem?
        try viewContext.performAndWaitThrowing {
            fetchedItem = try viewContext.existingObject(with: objectID) as? ClipItem
        }

        guard let item = fetchedItem else {
            throw ClipItemStoreError.creationFailed
        }

        return item
    }

    public static func deleteAll() {
        let store = ClipItemStore()
        try? store.deleteAllItems()
    }

    public func deleteAllItems() throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            let items = try context.fetch(request)
            for item in items {
                removeAssets(for: item)
                context.delete(item)
            }
            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            viewContext.refreshAllObjects()
        }
    }

    public func fetchRecentItems(limit: Int = 100) throws -> [ClipItem] {
        let context = persistence.viewContext
        var results: [ClipItem] = []
        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(format: "isTransient == NO")
            request.sortDescriptors = [
                NSSortDescriptor(key: "displayOrder", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            request.fetchLimit = limit
            request.relationshipKeyPathsForPrefetching = ["representations", "pinboards"]
            results = try context.fetch(request)
        }
        return results
    }

    @discardableResult
    public func cleanupExpiredItems(policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        guard let retentionDate = policy.retentionDate(reference: now) else {
            return 0
        }

        let context = persistence.newBackgroundContext()
        var deletedCount = 0
        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(
                format:
                    "createdAt < %@ AND isPinned == NO AND SUBQUERY(pinboards, $p, $p.isSystemClipboard == NO).@count == 0",
                retentionDate as NSDate
            )

            let expired = try context.fetch(request)
            deletedCount = expired.count
            for item in expired {
                removeAssets(for: item)
                context.delete(item)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        return deletedCount
    }

    @discardableResult
    public func updateTextItem(objectID: NSManagedObjectID, newText: String) throws -> ClipItem {
        let trimmedText = String(newText.prefix(10_000))
        let hash = Data(trimmedText.utf8).sha256Hex()
        let now = Date()

        let context = persistence.newBackgroundContext()
        var updatedObjectID: NSManagedObjectID?
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            item.primaryText = trimmedText
            item.searchableText = trimmedText.normalizedForSearch()
            item.modifiedAt = now
            item.contentHash = hash
            item.displayOrder = currentDisplayOrder(reference: now)
            item.byteCount = Int64(trimmedText.utf8.count)

            let primaryRep = item.representations?
                .sorted { $0.displayOrder < $1.displayOrder }
                .first

            if let rep = primaryRep {
                rep.textData = Data(trimmedText.utf8)
                rep.byteCount = Int64(trimmedText.utf8.count)
            } else {
                guard
                    let representation = NSEntityDescription.insertNewObject(
                        forEntityName: "ClipRepresentation", into: context) as? ClipRepresentation
                else {
                    throw ClipItemStoreError.creationFailed
                }
                representation.id = UUID()
                representation.uti = "public.utf8-plain-text"
                representation.kindValue = .plainText
                representation.displayOrder = 0
                representation.textData = Data(trimmedText.utf8)
                representation.byteCount = Int64(trimmedText.utf8.count)
                representation.clipItem = item
                item.addToRepresentations(representation)
            }

            try context.save()
            updatedObjectID = item.objectID
        }

        guard let updatedObjectID else {
            throw ClipItemStoreError.missingItem
        }

        let viewContext = persistence.viewContext
        var fetchedItem: ClipItem?
        try viewContext.performAndWaitThrowing {
            fetchedItem = try viewContext.existingObject(with: updatedObjectID) as? ClipItem
        }

        guard let item = fetchedItem else {
            throw ClipItemStoreError.missingItem
        }

        return item
    }

    public func deleteItem(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }
            removeAssets(for: item)
            context.delete(item)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    public func fetchPinboards() throws -> [Pinboard] {
        let context = persistence.viewContext
        var results: [Pinboard] = []
        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            results = try context.fetch(request)
        }
        return results
    }

    @discardableResult
    public func createPinboard(name: String, colorHex: String, iconName: String? = nil) throws
        -> Pinboard
    {
        let context = persistence.newBackgroundContext()
        var createdObjectID: NSManagedObjectID?
        try context.performAndWaitThrowing {
            guard
                let pinboard = NSEntityDescription.insertNewObject(
                    forEntityName: "Pinboard", into: context) as? Pinboard
            else {
                throw ClipItemStoreError.creationFailed
            }
            pinboard.id = UUID()
            pinboard.name = name
            pinboard.colorHex = colorHex
            pinboard.sortOrder = Int16((try? nextPinboardSortOrder(in: context)) ?? 0)
            pinboard.isSystemClipboard = false
            pinboard.createdAt = Date()
            pinboard.iconName = iconName

            try context.save()
            createdObjectID = pinboard.objectID
        }

        guard let objectID = createdObjectID else {
            throw ClipItemStoreError.creationFailed
        }

        let viewContext = persistence.viewContext
        var fetchedPinboard: Pinboard?
        try viewContext.performAndWaitThrowing {
            fetchedPinboard = try viewContext.existingObject(with: objectID) as? Pinboard
        }

        guard let pinboard = fetchedPinboard else {
            throw ClipItemStoreError.creationFailed
        }

        return pinboard
    }

    public func renamePinboard(objectID: NSManagedObjectID, name: String, colorHex: String? = nil)
        throws
    {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }
            pinboard.name = name
            if let colorHex {
                pinboard.colorHex = colorHex
            }
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let pinboard = try? viewContext.existingObject(with: objectID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    public func deletePinboard(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }
            context.delete(pinboard)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    public func renameItem(objectID: NSManagedObjectID, title: String?) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }
            item.customTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.customTitle?.isEmpty == true {
                item.customTitle = nil
            }
            item.modifiedAt = Date()
            if context.hasChanges {
                try context.save()
            }
        }
    }

    public func addItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem,
                let pinboard = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }
            item.addToPinboards(pinboard)
            try context.save()
        }
    }

    public func removeItem(objectID: NSManagedObjectID, fromPinboard pinboardID: NSManagedObjectID)
        throws
    {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem,
                let pinboard = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }
            item.removeFromPinboards(pinboard)
            try context.save()
        }
    }

    public func moveItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem,
                let target = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }

            let existingPinboards = item.pinboards ?? []
            for pinboard in existingPinboards
            where !pinboard.isSystemClipboard && pinboard.objectID != target.objectID {
                item.removeFromPinboards(pinboard)
            }

            item.addToPinboards(target)
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    public func updateThumbnail(
        objectID: NSManagedObjectID, data: Data, fileExtension: String = "png"
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

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    public func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws {
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
                    forEntityName: "LinkPreview", into: context) as? LinkPreview
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

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    public func markLinkPreviewFetchFailed(
        objectID: NSManagedObjectID, url: URL, fetchedAt: Date = Date()
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
                        forEntityName: "LinkPreview", into: context) as? LinkPreview
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

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    public func fetchPendingLinkPreviewTargets(limit: Int = 25) throws -> [(
        objectID: NSManagedObjectID, url: URL
    )] {
        let context = persistence.newBackgroundContext()
        var results: [(NSManagedObjectID, URL)] = []
        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(
                format: "needsLinkPreview == YES AND linkPreview == nil")
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            request.fetchLimit = limit
            let items = try context.fetch(request)
            for item in items {
                guard item.itemTypeValue == .url, let text = item.primaryText,
                    let url = URL(string: text)
                else {
                    continue
                }
                results.append((item.objectID, url))
            }
        }
        return results
    }

    public func markItemUsed(objectID: NSManagedObjectID, now: Date = Date()) throws {
        try markItemsUsed(objectIDs: [objectID], now: now)
    }

    public func markItemsUsed(objectIDs: [NSManagedObjectID], now: Date = Date()) throws {
        guard !objectIDs.isEmpty else { return }
        let context = persistence.newBackgroundContext()
        let baseOrder = currentDisplayOrder(reference: now) + Int64(objectIDs.count)

        try context.performAndWaitThrowing {
            for (index, objectID) in objectIDs.enumerated() {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }
                item.modifiedAt = now
                item.displayOrder = baseOrder - Int64(index)
            }
            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            for objectID in objectIDs {
                if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                    viewContext.refresh(item, mergeChanges: true)
                }
            }
        }
    }

    public func reorderItems(objectIDs: [NSManagedObjectID]) throws {
        guard !objectIDs.isEmpty else { return }
        let context = persistence.newBackgroundContext()
        let now = Date()
        let baseOrder = currentDisplayOrder(reference: now) + Int64(objectIDs.count)

        try context.performAndWaitThrowing {
            for (index, objectID) in objectIDs.enumerated() {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }
                item.displayOrder = baseOrder - Int64(index)
            }
            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            for objectID in objectIDs {
                if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                    viewContext.refresh(item, mergeChanges: true)
                }
            }
        }
    }

    public func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws {
        guard !orderedIDs.isEmpty else { return }
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            for (index, objectID) in orderedIDs.enumerated() {
                guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                    continue
                }
                pinboard.sortOrder = Int16(index)
            }
            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            for objectID in orderedIDs {
                if let pinboard = try? viewContext.existingObject(with: objectID) as? Pinboard {
                    viewContext.refresh(pinboard, mergeChanges: true)
                }
            }
        }
    }

    public func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws
        -> [ClipItem]
    {
        let normalized = query.normalizedForSearch()
        let context = persistence.viewContext
        var results: [ClipItem] = []
        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "searchableText CONTAINS[cd] %@", normalized)
            ]
            if let pinboardID {
                predicates.append(
                    NSPredicate(format: "ANY pinboards.id == %@", pinboardID as CVarArg))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: "displayOrder", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            request.fetchLimit = limit
            request.relationshipKeyPathsForPrefetching = ["representations", "pinboards"]
            results = try context.fetch(request)
        }
        return results
    }

    private func computeContentHash(
        primaryText: String?,
        representations: [ClipRepresentationPayload]
    ) throws -> String {
        if let primaryText, !primaryText.isEmpty {
            return Data(primaryText.utf8).sha256Hex()
        }

        let sorted = representations.sorted { $0.displayOrder < $1.displayOrder }
        for rep in sorted {
            if let text = rep.text, !text.isEmpty {
                return Data(text.utf8).sha256Hex()
            }
            if let data = rep.data, !data.isEmpty {
                return data.sha256Hex()
            }
        }

        throw ClipItemStoreError.missingContent
    }

    private func deriveSearchableText(
        primaryText: String?,
        representations: [ClipRepresentationPayload]
    ) -> String? {
        if let primaryText, !primaryText.isEmpty {
            return primaryText.normalizedForSearch()
        }

        let fallback = representations.compactMap { $0.text }.first
        return fallback?.normalizedForSearch()
    }

    private func fetchExistingItem(hash: String, in context: NSManagedObjectContext) throws
        -> ClipItem?
    {
        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", hash)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func currentDisplayOrder(reference: Date = Date()) -> Int64 {
        Int64(reference.timeIntervalSince1970 * 1000)
    }

    private func nextPinboardSortOrder(in context: NSManagedObjectContext) throws -> Int {
        let request = Pinboard.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1
        if let last = try context.fetch(request).first {
            return Int(last.sortOrder) + 1
        }
        return 0
    }

    private func fetchOrCreateSystemClipboardPinboard(in context: NSManagedObjectContext) throws
        -> Pinboard
    {
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemClipboard == YES")
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            return existing
        }

        guard
            let pinboard = NSEntityDescription.insertNewObject(
                forEntityName: "Pinboard", into: context) as? Pinboard
        else {
            throw ClipItemStoreError.creationFailed
        }
        pinboard.id = UUID()
        pinboard.name = "Clipboard"
        pinboard.colorHex = "#808080"
        pinboard.sortOrder = 0
        pinboard.isSystemClipboard = true
        pinboard.createdAt = Date()
        return pinboard
    }

    private func removeAssets(for item: ClipItem) {
        let representations = item.representations ?? []
        for representation in representations {
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

    public func saveChanges() throws {
        try persistence.saveViewContextIfNeeded()
    }
}

extension ClipItemStore: @unchecked Sendable {}
