import CoreData
import Foundation
import OSLog

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

final class ClipItemRepository {
    private static let logger = Logger(
        subsystem: "com.paste.clipboard.core",
        category: "ClipItemRepository"
    )

    private let persistence: PersistenceController
    private let assetStore: AssetStore
    private let pinboardRepository: any PinboardRepositoryProtocol
    private let searchService: any SearchServicing
    private let assetManagementService: any AssetManagementServicing
    private let deduplicationService: any ClipItemDeduplicationServicing
    private let assetThresholdBytes = 256 * 1024

    init(
        persistence: PersistenceController,
        assetStore: AssetStore,
        pinboardRepository: any PinboardRepositoryProtocol,
        searchService: any SearchServicing,
        assetManagementService: any AssetManagementServicing,
        deduplicationService: any ClipItemDeduplicationServicing = ClipItemDeduplicationService()
    ) {
        self.persistence = persistence
        self.assetStore = assetStore
        self.pinboardRepository = pinboardRepository
        self.searchService = searchService
        self.assetManagementService = assetManagementService
        self.deduplicationService = deduplicationService
    }

    convenience init(
        persistence: PersistenceController = .shared,
        assetStore: AssetStore = .shared
    ) {
        let pinboardRepository = PinboardRepository(persistence: persistence)
        let searchService = SearchService(persistence: persistence)
        let assetManagementService = AssetManagementService(
            persistence: persistence,
            assetStore: assetStore
        )

        self.init(
            persistence: persistence,
            assetStore: assetStore,
            pinboardRepository: pinboardRepository,
            searchService: searchService,
            assetManagementService: assetManagementService
        )
    }

    @discardableResult
    func createTextItem(
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
    func createItem(
        payload: ClipItemPayload,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        guard !payload.representations.isEmpty else {
            throw ClipItemStoreError.missingContent
        }

        let now = Date()
        let displayOrder = currentDisplayOrder(reference: now)
        let hash = try deduplicationService.computeContentHash(
            primaryText: payload.primaryText,
            representations: payload.representations
        )

        let context = persistence.newBackgroundContext()
        var createdObjectID: NSManagedObjectID?

        try context.performAndWaitThrowing {
            if let existing = try deduplicationService.fetchExistingItem(hash: hash, in: context) {
                existing.modifiedAt = now
                existing.displayOrder = displayOrder
                try context.save()
                createdObjectID = existing.objectID
                return
            }

            guard
                let item = NSEntityDescription.insertNewObject(
                    forEntityName: "ClipItem",
                    into: context
                ) as? ClipItem
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
            item.searchableText = searchService.deriveSearchableText(
                primaryText: payload.primaryText,
                representations: payload.representations
            )
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
                            data: data,
                            fileExtension: repPayload.fileExtension
                        )
                    } else {
                        representation.binaryData = data
                    }
                }

                representation.byteCount = repBytes
                totalBytes += repBytes
                item.addToRepresentations(representation)
            }

            item.byteCount = totalBytes

            let clipboardPinboard = try pinboardRepository.fetchOrCreateSystemClipboardPinboard(
                in: context
            )
            item.addToPinboards(clipboardPinboard)

            try context.save()
            createdObjectID = item.objectID
        }

        guard let objectID = createdObjectID else {
            throw ClipItemStoreError.creationFailed
        }

        return try fetchRefreshedItemInViewContext(objectID: objectID)
    }

    func deleteAllItems() throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.fetchLimit = 200

            while true {
                let items = try context.fetch(request)
                guard !items.isEmpty else { break }

                let deletedIDs = items.map(\.id.uuidString).joined(separator: ",")
                let cleanupPlans = items.map { assetManagementService.makeAssetCleanupPlan(for: $0) }

                for item in items {
                    context.delete(item)
                }

                if context.hasChanges {
                    try context.save()
                }

                for plan in cleanupPlans {
                    assetManagementService.executeAssetCleanupPlan(plan)
                }

                Self.logger.notice(
                    "deleteAllItems removed \(items.count, privacy: .public) items [ids: \(deletedIDs, privacy: .private(mask: .hash))]"
                )

                context.reset()
            }
        }
    }

    func fetchRecentItems(limit: Int = 100) throws -> [ClipItem] {
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
            request.returnsObjectsAsFaults = false
            request.relationshipKeyPathsForPrefetching = [
                "representations",
                "pinboards",
                "linkPreview",
                "stackEntries",
            ]
            results = try context.fetch(request)
        }

        return results
    }

    @discardableResult
    func updateTextItem(objectID: NSManagedObjectID, newText: String) throws -> ClipItem {
        let trimmedText = String(newText.prefix(10_000))
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
            item.contentHash = Data(trimmedText.utf8).sha256Hex()
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
                        forEntityName: "ClipRepresentation",
                        into: context
                    ) as? ClipRepresentation
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

        return try fetchRefreshedItemInViewContext(objectID: updatedObjectID)
    }

    @discardableResult
    func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data) throws
        -> ClipItem
    {
        let trimmedText = String(newText.prefix(10_000))
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
            item.contentHash = Data(trimmedText.utf8).sha256Hex()
            item.displayOrder = currentDisplayOrder(reference: now)
            item.itemTypeValue = .richText

            let plainTextData = Data(trimmedText.utf8)
            let existingRepresentations = item.representations ?? []

            let plainRep =
                existingRepresentations.first(where: { $0.kindValue == .plainText })
                ?? {
                    guard
                        let representation = NSEntityDescription.insertNewObject(
                            forEntityName: "ClipRepresentation",
                            into: context
                        ) as? ClipRepresentation
                    else {
                        return nil
                    }

                    representation.id = UUID()
                    representation.clipItem = item
                    item.addToRepresentations(representation)
                    return representation
                }()

            guard let plainRep else {
                throw ClipItemStoreError.creationFailed
            }

            plainRep.uti = "public.utf8-plain-text"
            plainRep.kindValue = .plainText
            plainRep.displayOrder = 0
            plainRep.fileExtension = nil
            plainRep.binaryData = nil
            plainRep.assetRef = nil
            plainRep.textData = plainTextData
            plainRep.byteCount = Int64(plainTextData.count)

            let richRep =
                existingRepresentations.first(where: { $0.kindValue == .rtf })
                ?? {
                    guard
                        let representation = NSEntityDescription.insertNewObject(
                            forEntityName: "ClipRepresentation",
                            into: context
                        ) as? ClipRepresentation
                    else {
                        return nil
                    }

                    representation.id = UUID()
                    representation.clipItem = item
                    item.addToRepresentations(representation)
                    return representation
                }()

            guard let richRep else {
                throw ClipItemStoreError.creationFailed
            }

            richRep.uti = "public.rtf"
            richRep.kindValue = .rtf
            richRep.displayOrder = 1
            richRep.fileExtension = "rtf"
            richRep.binaryData = rtfData
            richRep.assetRef = nil
            richRep.textData = nil
            richRep.byteCount = Int64(rtfData.count)

            // Rich text edit should replace stale HTML representation, if any.
            for rep in existingRepresentations where rep.kindValue == .html {
                item.removeFromRepresentations(rep)
                context.delete(rep)
            }

            item.byteCount = (item.representations ?? []).reduce(Int64(0)) { partial, rep in
                partial + rep.byteCount
            }

            try context.save()
            updatedObjectID = item.objectID
        }

        guard let updatedObjectID else {
            throw ClipItemStoreError.missingItem
        }

        return try fetchRefreshedItemInViewContext(objectID: updatedObjectID)
    }

    @discardableResult
    func updateItem(objectID: NSManagedObjectID, payload: ClipItemPayload) throws -> ClipItem {
        guard !payload.representations.isEmpty else {
            throw ClipItemStoreError.missingContent
        }

        let now = Date()
        let displayOrder = currentDisplayOrder(reference: now)
        let hash = try deduplicationService.computeContentHash(
            primaryText: payload.primaryText,
            representations: payload.representations
        )

        let context = persistence.newBackgroundContext()
        var updatedObjectID: NSManagedObjectID?
        var previousAssetsCleanupPlan: AssetCleanupPlan?

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            previousAssetsCleanupPlan = assetManagementService.makeAssetCleanupPlan(for: item)
            for rep in item.representations ?? [] {
                item.removeFromRepresentations(rep)
                context.delete(rep)
            }

            item.modifiedAt = now
            item.displayOrder = displayOrder
            item.itemTypeValue = payload.itemType
            item.primaryText = payload.primaryText
            item.searchableText = searchService.deriveSearchableText(
                primaryText: payload.primaryText,
                representations: payload.representations
            )
            item.contentHash = hash
            item.needsLinkPreview = payload.needsLinkPreview
            item.isSensitive = payload.isSensitive
            item.isTransient = payload.isTransient

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
                } else {
                    representation.textData = nil
                }

                if let data = repPayload.data {
                    repBytes += Int64(data.count)
                    if data.count > assetThresholdBytes {
                        representation.assetRef = try assetStore.store(
                            data: data,
                            fileExtension: repPayload.fileExtension
                        )
                        representation.binaryData = nil
                    } else {
                        representation.binaryData = data
                        representation.assetRef = nil
                    }
                } else {
                    representation.binaryData = nil
                    representation.assetRef = nil
                }

                representation.byteCount = repBytes
                totalBytes += repBytes
                item.addToRepresentations(representation)
            }

            item.byteCount = totalBytes

            try context.save()
            updatedObjectID = item.objectID
        }

        if let previousAssetsCleanupPlan {
            assetManagementService.executeAssetCleanupPlan(previousAssetsCleanupPlan)
        }

        guard let updatedObjectID else {
            throw ClipItemStoreError.missingItem
        }

        return try fetchRefreshedItemInViewContext(objectID: updatedObjectID)
    }

    func toggleFavorite(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            item.isPinned.toggle()
            item.modifiedAt = Date()

            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    func deleteItem(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()
        var cleanupPlan: AssetCleanupPlan?

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            cleanupPlan = assetManagementService.makeAssetCleanupPlan(for: item)
            for stackEntry in item.stackEntries ?? [] {
                context.delete(stackEntry)
            }
            context.delete(item)

            if context.hasChanges {
                try context.save()
            }
        }

        if let cleanupPlan {
            assetManagementService.executeAssetCleanupPlan(cleanupPlan)
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    func renameItem(objectID: NSManagedObjectID, title: String?) throws {
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

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    func updateFileName(objectID: NSManagedObjectID, newFileName: String) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            if item.itemTypeValue == .file, let oldPath = item.primaryText {
                let oldURL = URL(fileURLWithPath: oldPath)
                let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFileName)

                if FileManager.default.fileExists(atPath: oldPath) {
                    try? FileManager.default.moveItem(atPath: oldPath, toPath: newURL.path)
                }

                item.primaryText = newURL.path

                if let representations = item.representations {
                    for rep in representations where rep.kindValue == .fileURL {
                        rep.textData = Data(newURL.path.utf8)
                        rep.byteCount = Int64(newURL.path.utf8.count)
                    }
                }
            }

            let now = Date()
            item.modifiedAt = now
            item.displayOrder = currentDisplayOrder(reference: now)
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    func saveChanges() throws {
        try persistence.saveViewContextIfNeeded()
    }

    private func fetchItemInViewContext(objectID: NSManagedObjectID) throws -> ClipItem {
        let viewContext = persistence.viewContext
        var fetchedItem: ClipItem?

        try viewContext.performAndWaitThrowing {
            fetchedItem = try viewContext.existingObject(with: objectID) as? ClipItem
        }

        guard let item = fetchedItem else {
            throw ClipItemStoreError.missingItem
        }

        return item
    }

    private func fetchRefreshedItemInViewContext(objectID: NSManagedObjectID) throws -> ClipItem {
        let viewContext = persistence.viewContext
        var fetchedItem: ClipItem?

        try viewContext.performAndWaitThrowing {
            if let item = try viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
                fetchedItem = item
            }
        }

        guard let item = fetchedItem else {
            throw ClipItemStoreError.missingItem
        }

        return item
    }

    private func currentDisplayOrder(reference: Date = Date()) -> Int64 {
        Int64(reference.timeIntervalSince1970 * 1000)
    }
}

// SAFETY: ClipItemRepository is immutable after initialization. Core Data and file-system work is
// performed on the appropriate context queue via `performAndWaitThrowing`.
extension ClipItemRepository: @unchecked Sendable {}

extension ClipItemRepository: ClipItemRepositoryProtocol {}
