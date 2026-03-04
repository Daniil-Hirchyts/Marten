import CoreData
import Foundation
import OSLog
import UniformTypeIdentifiers

public struct SourceAppInfo: Sendable {
    public let bundleID: String?
    public let name: String?
    public let iconData: Data?

    public init(bundleID: String?, name: String?, iconData: Data? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconData = iconData
    }
}

public enum ClipItemStoreError: Error, Equatable {
    case creationFailed
    case missingItem
    case missingContent
    case unsupportedTypeConversion
    case invalidURLForTypeConversion
}

extension ClipItemStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .creationFailed:
            return "Couldn't create the item."
        case .missingItem:
            return "The item no longer exists."
        case .missingContent:
            return "Item content is empty."
        case .unsupportedTypeConversion:
            return "This card type can't be converted."
        case .invalidURLForTypeConversion:
            return "Enter a valid URL before converting to Link."
        }
    }
}

final class ClipItemRepository {
    private static let logger = Logger(
        subsystem: "com.hirchyts.marten.core",
        category: "ClipItemRepository"
    )
    private static let convertibleTextItemTypes: Set<ItemType> = [
        .text,
        .url,
        .code,
        .color,
    ]

    private let persistence: PersistenceController
    private let assetStore: AssetStore
    private let pinboardRepository: any PinboardRepositoryProtocol
    private let searchService: any SearchServicing
    private let assetManagementService: any AssetManagementServicing
    private let deduplicationService: any ClipItemDeduplicationServicing
    private let assetThresholdBytes = 256 * 1024
    private let syncableBinaryKinds: Set<RepresentationKind> = [.rtf, .png, .jpeg, .tiff, .pdf, .custom]

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
                existing.lastModifiedBy = DeviceIdentifier.currentDeviceName
                existing.lastModifiedAt = now
                existing.displayOrder = displayOrder
                if let sourceApp {
                    let previousBundleID = existing.sourceAppBundleID
                    let previousName = existing.sourceAppName
                    existing.sourceAppBundleID = sourceApp.bundleID
                    existing.sourceAppName = sourceApp.name
                    if let iconData = sourceApp.iconData, !iconData.isEmpty {
                        existing.sourceAppIconData = iconData
                    } else if sourceApp.bundleID != previousBundleID || sourceApp.name != previousName {
                        existing.sourceAppIconData = nil
                    }
                }
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
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
            item.displayOrder = displayOrder
            item.sourceAppBundleID = sourceApp?.bundleID
            item.sourceAppName = sourceApp?.name
            item.sourceAppIconData = sourceApp?.iconData
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
                    try storeBinaryPayload(
                        data,
                        for: representation,
                        kind: repPayload.kind,
                        fileExtension: repPayload.fileExtension
                    )
                }

                representation.byteCount = repBytes
                totalBytes += repBytes
                item.addToRepresentations(representation)
            }

            item.byteCount = totalBytes

            let clipboardPinboard = try pinboardRepository.fetchOrCreateSystemMartenPinboard(
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

    func deleteItemsFromThisDevice() throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()

            // Predicate matching "This Device" logic from SearchService
            let thisDeviceMarkers = [
                "This Device",
                "local",
                "local device",
                "current device",
            ]
            let markerPredicates = thisDeviceMarkers.map {
                NSPredicate(format: "lastModifiedBy ==[c] %@", $0)
            }
            request.predicate = NSCompoundPredicate(
                orPredicateWithSubpredicates: [
                    NSPredicate(format: "lastModifiedBy == nil"),
                    NSPredicate(format: "lastModifiedBy == ''"),
                    NSPredicate(format: "lastModifiedBy == %@", DeviceIdentifier.currentDeviceName),
                ] + markerPredicates
            )

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
                    "deleteItemsFromThisDevice removed \(items.count, privacy: .public) items [ids: \(deletedIDs, privacy: .private(mask: .hash))]"
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

    func fetchItems(
        primaryText: String,
        itemType: ItemType,
        limit: Int = 50
    ) throws -> [ClipItem] {
        let context = persistence.viewContext
        var results: [ClipItem] = []

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isTransient == NO"),
                itemTypePredicate(for: itemType),
                NSPredicate(format: "primaryText == %@", primaryText),
            ])
            request.sortDescriptors = [
                NSSortDescriptor(key: "displayOrder", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            request.fetchLimit = max(1, limit)
            request.returnsObjectsAsFaults = false
            request.relationshipKeyPathsForPrefetching = ["pinboards"]
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
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
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
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
            item.contentHash = Data(trimmedText.utf8).sha256Hex()
            item.displayOrder = currentDisplayOrder(reference: now)
            item.itemTypeValue = .text

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
            try storeBinaryPayload(rtfData, for: richRep, kind: .rtf, fileExtension: "rtf")
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
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
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
                    try storeBinaryPayload(
                        data,
                        for: representation,
                        kind: repPayload.kind,
                        fileExtension: repPayload.fileExtension
                    )
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

    @discardableResult
    func updateItemType(objectID: NSManagedObjectID, newType: ItemType) throws -> ClipItem {
        guard Self.convertibleTextItemTypes.contains(newType) else {
            throw ClipItemStoreError.unsupportedTypeConversion
        }

        let now = Date()
        let displayOrder = currentDisplayOrder(reference: now)
        let context = persistence.newBackgroundContext()
        var updatedObjectID: NSManagedObjectID?

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            let currentType = item.itemTypeValue
            guard Self.convertibleTextItemTypes.contains(currentType) else {
                throw ClipItemStoreError.unsupportedTypeConversion
            }
            guard currentType != newType else {
                updatedObjectID = item.objectID
                return
            }

            guard var normalizedText = normalizedConversionText(for: item) else {
                throw ClipItemStoreError.missingContent
            }

            if newType == .url {
                guard let normalizedURLText = normalizedURLString(from: normalizedText) else {
                    throw ClipItemStoreError.invalidURLForTypeConversion
                }
                normalizedText = normalizedURLText
            }

            let representations = typeConversionRepresentations(
                for: newType,
                text: normalizedText
            )

            if newType != .url, let existingPreview = item.linkPreview {
                if let existingImagePath = existingPreview.imagePath {
                    try? FileManager.default.removeItem(atPath: existingImagePath)
                }
                item.linkPreview = nil
                context.delete(existingPreview)
            }

            for representation in item.representations ?? [] {
                item.removeFromRepresentations(representation)
                context.delete(representation)
            }

            item.modifiedAt = now
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
            item.displayOrder = displayOrder
            item.itemTypeValue = newType
            item.primaryText = normalizedText
            item.searchableText = searchService.deriveSearchableText(
                primaryText: normalizedText,
                representations: representations
            )
            item.contentHash = Data(normalizedText.utf8).sha256Hex()
            item.needsLinkPreview = (newType == .url)

            var totalBytes: Int64 = 0
            let sortedRepresentations = representations.sorted {
                $0.displayOrder < $1.displayOrder
            }

            for representationPayload in sortedRepresentations {
                guard
                    let representation = NSEntityDescription.insertNewObject(
                        forEntityName: "ClipRepresentation",
                        into: context
                    ) as? ClipRepresentation
                else {
                    throw ClipItemStoreError.creationFailed
                }

                representation.id = UUID()
                representation.uti = representationPayload.uti
                representation.kindValue = representationPayload.kind
                representation.displayOrder = representationPayload.displayOrder
                representation.fileExtension = representationPayload.fileExtension
                representation.clipItem = item

                var byteCount: Int64 = 0
                if let text = representationPayload.text, !text.isEmpty {
                    let textData = Data(text.utf8)
                    representation.textData = textData
                    byteCount += Int64(textData.count)
                }

                if let data = representationPayload.data {
                    byteCount += Int64(data.count)
                    try storeBinaryPayload(
                        data,
                        for: representation,
                        kind: representationPayload.kind,
                        fileExtension: representationPayload.fileExtension
                    )
                } else {
                    representation.binaryData = nil
                    representation.assetRef = nil
                }

                representation.byteCount = byteCount
                totalBytes += byteCount
                item.addToRepresentations(representation)
            }

            item.byteCount = totalBytes

            try context.save()
            updatedObjectID = item.objectID
        }

        guard let updatedObjectID else {
            throw ClipItemStoreError.missingItem
        }

        return try fetchRefreshedItemInViewContext(objectID: updatedObjectID)
    }

    func togglePin(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                throw ClipItemStoreError.missingItem
            }

            item.isPinned.toggle()
            if item.isPinned {
                item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
            }
            let now = Date()
            item.modifiedAt = now
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now

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

    func toggleFavorite(objectID: NSManagedObjectID) throws {
        try togglePin(objectID: objectID)
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

            let now = Date()
            item.modifiedAt = now
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
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

            if item.itemTypeValue == .file {
                item.primaryText = ManagedFileAccess.normalizedStoredFileName(newFileName) ?? newFileName
                item.searchableText = item.primaryText?.normalizedForSearch()
            }

            let now = Date()
            item.modifiedAt = now
            item.lastModifiedBy = DeviceIdentifier.currentDeviceName
            item.lastModifiedAt = now
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

    /// Stamps all items with nil/empty `lastModifiedBy` with the current device name.
    /// Intended to be called once per device to backfill existing data.
    ///
    /// - Returns: The number of items updated.
    @discardableResult
    func backfillDeviceAttribution() throws -> Int {
        let context = persistence.newBackgroundContext()
        let deviceName = DeviceIdentifier.currentDeviceName
        let now = Date()
        var totalUpdated = 0

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "lastModifiedBy == nil"),
                NSPredicate(format: "lastModifiedBy == ''"),
            ])
            request.fetchLimit = 200

            while true {
                let items = try context.fetch(request)
                guard !items.isEmpty else { break }

                for item in items {
                    item.lastModifiedBy = deviceName
                    item.lastModifiedAt = now
                }

                if context.hasChanges {
                    try context.save()
                }

                totalUpdated += items.count
                context.reset()
            }
        }

        if totalUpdated > 0 {
            Self.logger.notice("backfillDeviceAttribution updated \(totalUpdated, privacy: .public) items with device name")
        }

        return totalUpdated
    }

    /// Recomputes content hashes for legacy asset-backed items that were hashed from
    /// placeholder titles such as "Image" instead of their binary payload.
    @discardableResult
    func backfillBinaryContentHashes() throws -> Int {
        let context = persistence.newBackgroundContext()
        var updatedCount = 0

        try context.performAndWaitThrowing {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "ClipItem")
            request.resultType = .managedObjectIDResultType
            request.fetchBatchSize = 50
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "ANY representations.assetRef != nil"),
                NSPredicate(format: "ANY representations.binaryData != nil"),
            ])

            let objectIDs = try context.fetch(request)

            for (index, objectID) in objectIDs.enumerated() {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }

                let hashingPayloads = representationPayloadsForHashing(from: item)
                guard !hashingPayloads.isEmpty else { continue }

                let recomputedHash = try deduplicationService.computeContentHash(
                    primaryText: item.primaryText,
                    representations: hashingPayloads
                )

                guard recomputedHash != item.contentHash else { continue }

                if let existing = try deduplicationService.fetchExistingItem(hash: recomputedHash, in: context),
                   existing.objectID != item.objectID {
                    continue
                }

                item.contentHash = recomputedHash
                updatedCount += 1

                if (index + 1).isMultiple(of: 50), context.hasChanges {
                    try context.save()
                    context.reset()
                }
            }

            if context.hasChanges {
                try context.save()
            }
        }

        if updatedCount > 0 {
            Self.logger.notice(
                "backfillBinaryContentHashes updated \(updatedCount, privacy: .public) items"
            )
        }

        return updatedCount
    }

    /// Migrates syncable binary payloads from inline `binaryData` storage to `assetRef` files.
    /// Returns the number of representations migrated.
    @discardableResult
    func migrateSyncableBinaryRepresentationsToAssets() throws -> Int {
        let context = persistence.newBackgroundContext()
        var migratedCount = 0
        let syncableKindPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: syncableBinaryKinds.map {
            NSPredicate(format: "kind == %d", $0.rawValue)
        })
        let candidatePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "binaryData != nil"),
            NSPredicate(format: "assetRef == nil"),
            NSPredicate(format: "kind != %d", RepresentationKind.fileURL.rawValue),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                syncableKindPredicate,
                NSPredicate(format: "byteCount > %d", assetThresholdBytes),
            ]),
        ])

        try context.performAndWaitThrowing {
            while true {
                let idRequest = NSFetchRequest<NSManagedObjectID>(entityName: "ClipRepresentation")
                idRequest.resultType = .managedObjectIDResultType
                idRequest.predicate = candidatePredicate
                idRequest.fetchLimit = 25
                idRequest.fetchBatchSize = 25

                let objectIDs = try context.fetch(idRequest)
                guard !objectIDs.isEmpty else { break }

                for objectID in objectIDs {
                    guard
                        let representation = try context.existingObject(with: objectID) as? ClipRepresentation,
                        let data = representation.binaryData
                    else {
                        continue
                    }
                    guard shouldStoreAsAsset(kind: representation.kindValue, byteCount: data.count) else {
                        // Keep byteCount aligned with payload size so stale metadata cannot
                        // repeatedly select this record in subsequent batches.
                        let actualByteCount = Int64(data.count)
                        if representation.byteCount != actualByteCount {
                            representation.byteCount = actualByteCount
                        }
                        continue
                    }

                    representation.assetRef = try assetStore.store(
                        data: data,
                        fileExtension: representation.fileExtension
                    )
                    representation.binaryData = nil
                    migratedCount += 1
                }

                if context.hasChanges {
                    try context.save()
                }
                context.reset()
            }
        }

        if migratedCount > 0 {
            Self.logger.notice(
                "migrateSyncableBinaryRepresentationsToAssets migrated \(migratedCount, privacy: .public) representations"
            )
        }

        return migratedCount
    }

    /// Repairs legacy iOS image items that were stored as `.fileURL` representations pointing
    /// to temporary local files instead of syncable image assets.
    ///
    /// Returns the number of representations converted to asset-backed image payloads.
    @discardableResult
    func backfillImageFileURLRepresentations() throws -> Int {
        let context = persistence.newBackgroundContext()
        var repairedCount = 0
        let candidatePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "kind == %d", RepresentationKind.fileURL.rawValue),
            NSPredicate(format: "clipItem.itemType == %d", ItemType.image.rawValue),
            NSPredicate(format: "assetRef == nil"),
        ])

        try context.performAndWaitThrowing {
            while true {
                let idRequest = NSFetchRequest<NSManagedObjectID>(entityName: "ClipRepresentation")
                idRequest.resultType = .managedObjectIDResultType
                idRequest.predicate = candidatePredicate
                idRequest.fetchLimit = 25
                idRequest.fetchBatchSize = 25

                let objectIDs = try context.fetch(idRequest)
                guard !objectIDs.isEmpty else { break }

                for objectID in objectIDs {
                    guard
                        let representation = try context.existingObject(with: objectID)
                            as? ClipRepresentation,
                        let item = representation.clipItem,
                        let sourceURL = resolvedLegacyImageFileURL(for: representation),
                        let imageType = inferredImageType(for: sourceURL, fallbackUTI: representation.uti),
                        imageType.conforms(to: .image),
                        let imageData = loadDataFromResolvedFileURL(sourceURL),
                        !imageData.isEmpty
                    else {
                        continue
                    }

                    let (kind, fileExtension) = normalizedImageRepresentationMetadata(
                        type: imageType,
                        sourceURL: sourceURL
                    )

                    representation.kindValue = kind
                    representation.uti = imageType.identifier
                    representation.fileExtension = fileExtension
                    representation.textData = nil
                    try storeBinaryPayload(
                        imageData,
                        for: representation,
                        kind: kind,
                        fileExtension: fileExtension
                    )
                    representation.byteCount = Int64(imageData.count)

                    item.byteCount = Int64((item.representations ?? []).reduce(0) { partialResult, rep in
                        partialResult + Int(rep.byteCount)
                    })
                    item.contentHash = try deduplicationService.computeContentHash(
                        primaryText: item.primaryText,
                        representations: representationPayloadsForHashing(from: item)
                    )

                    repairedCount += 1
                }

                if context.hasChanges {
                    try context.save()
                }
                context.reset()
            }
        }

        if repairedCount > 0 {
            Self.logger.notice(
                "backfillImageFileURLRepresentations repaired \(repairedCount, privacy: .public) representations"
            )
        }

        return repairedCount
    }

    @discardableResult
    func repairInvalidFileExtensions() throws -> Int {
        let context = persistence.newBackgroundContext()
        var repairedCount = 0

        try context.performAndWaitThrowing {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "ClipRepresentation")
            request.resultType = .managedObjectIDResultType
            request.predicate = NSPredicate(format: "fileExtension != nil")
            let objectIDs = try context.fetch(request)

            for objectID in objectIDs {
                guard let representation = try context.existingObject(with: objectID) as? ClipRepresentation else {
                    continue
                }
                guard let ext = representation.fileExtension, ext.count >= 40 else { continue }
                
                let uti = representation.uti
                let preferred: String
                if let type = UTType(uti), let typeExt = type.preferredFilenameExtension {
                    preferred = typeExt
                } else if representation.kindValue == .png {
                    preferred = "png"
                } else if representation.kindValue == .jpeg {
                    preferred = "jpg"
                } else if representation.kindValue == .tiff {
                    preferred = "tiff"
                } else {
                    continue
                }

                if let assetRef = representation.assetRef {
                    let oldURL = AssetStore.shared.urlForAsset(assetRef, fileExtension: ext)
                    let newURL = AssetStore.shared.urlForAsset(assetRef, fileExtension: preferred)
                    if FileManager.default.fileExists(atPath: oldURL.path) && !FileManager.default.fileExists(atPath: newURL.path) {
                        try? FileManager.default.moveItem(at: oldURL, to: newURL)
                    }
                }
                
                representation.fileExtension = preferred
                representation.clipItem?.modifiedAt = Date()
                repairedCount += 1
            }

            if context.hasChanges {
                try context.save()
            }
        }

        if repairedCount > 0 {
            Self.logger.notice("repairInvalidFileExtensions repaired \(repairedCount, privacy: .public) extensions")
        }

        return repairedCount
    }

    func countItemsMissingRepresentations() throws -> Int {
        let context = persistence.newBackgroundContext()
        var count = 0

        try context.performAndWaitThrowing {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ClipItem")
            request.predicate = NSPredicate(format: "representations.@count == 0")
            count = try context.count(for: request)
        }

        return count
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

    private func normalizedConversionText(for item: ClipItem) -> String? {
        guard let sourceText = item.plainTextContent ?? item.primaryText else {
            return nil
        }

        let clippedText = String(sourceText.prefix(10_000))
        guard !clippedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return clippedText
    }

    private func typeConversionRepresentations(
        for newType: ItemType,
        text: String
    ) -> [ClipRepresentationPayload] {
        if newType == .url {
            return [
                ClipRepresentationPayload(
                    kind: .url,
                    uti: "public.url",
                    text: text
                )
            ]
        }

        return [.plainText(text)]
    }

    private func itemTypePredicate(for type: ItemType) -> NSPredicate {
        if type == .text {
            return NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "itemType == %d", ItemType.text.rawValue),
                NSPredicate(format: "itemType == %d", ItemType.richText.rawValue),
            ])
        }

        return NSPredicate(format: "itemType == %d", type.rawValue)
    }

    private func normalizedURLString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            return parsed.absoluteString
        }

        let prefixed = "https://\(trimmed)"
        guard let parsed = URL(string: prefixed), parsed.host != nil else {
            return nil
        }
        return parsed.absoluteString
    }

    private func currentDisplayOrder(reference: Date = Date()) -> Int64 {
        Int64(reference.timeIntervalSince1970 * 1000)
    }

    private func resolvedLegacyImageFileURL(for representation: ClipRepresentation) -> URL? {
        if let bookmarkData = representation.binaryData,
            let bookmarkedURL = resolveBookmarkedFileURL(from: bookmarkData)
        {
            return bookmarkedURL
        }

        guard
            let textData = representation.textData,
            let raw = String(data: textData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }

        if let parsed = URL(string: raw), parsed.isFileURL {
            return parsed
        }

        return URL(fileURLWithPath: raw)
    }

    private func resolveBookmarkedFileURL(from data: Data) -> URL? {
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
        }

        #if os(macOS)
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
        }
        #endif

        return nil
    }

    private func inferredImageType(for sourceURL: URL, fallbackUTI: String?) -> UTType? {
        if let contentType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }

        if let type = UTType(filenameExtension: sourceURL.pathExtension) {
            return type
        }

        if let fallbackUTI, let type = UTType(fallbackUTI) {
            return type
        }

        return nil
    }

    private func normalizedImageRepresentationMetadata(
        type: UTType,
        sourceURL: URL
    ) -> (kind: RepresentationKind, fileExtension: String) {
        let pathExt = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedExtension = pathExt.count < 10 && !pathExt.isEmpty ? pathExt : (type.preferredFilenameExtension ?? "")

        if type.conforms(to: .png) {
            return (.png, normalizedExtension.isEmpty ? "png" : normalizedExtension)
        }

        if type.conforms(to: .tiff) {
            return (.tiff, normalizedExtension.isEmpty ? "tiff" : normalizedExtension)
        }

        if type.conforms(to: .image) {
            let fallbackExtension: String
            switch normalizedExtension {
            case "heic", "heif", "jpeg", "jpg", "gif", "bmp", "webp":
                fallbackExtension = normalizedExtension
            default:
                fallbackExtension = "jpg"
            }

            return (.jpeg, fallbackExtension)
        }

        return (.jpeg, normalizedExtension.isEmpty ? "jpg" : normalizedExtension)
    }

    private func loadDataFromResolvedFileURL(_ url: URL) -> Data? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try? Data(contentsOf: url)
    }

    private func storeBinaryPayload(
        _ data: Data,
        for representation: ClipRepresentation,
        kind: RepresentationKind,
        fileExtension: String?
    ) throws {
        if shouldStoreAsAsset(kind: kind, byteCount: data.count) {
            representation.assetRef = try assetStore.store(
                data: data,
                fileExtension: fileExtension
            )
            representation.binaryData = nil
            return
        }

        representation.binaryData = data
        representation.assetRef = nil
    }

    private func shouldStoreAsAsset(kind: RepresentationKind, byteCount: Int) -> Bool {
        guard kind != .fileURL else {
            return false
        }

        if syncableBinaryKinds.contains(kind) {
            return true
        }

        return byteCount > assetThresholdBytes
    }

    private func representationPayloadsForHashing(from item: ClipItem) -> [ClipRepresentationPayload] {
        let sortedRepresentations = (item.representations ?? []).sorted {
            $0.displayOrder < $1.displayOrder
        }

        return sortedRepresentations.map { representation in
            let text: String? = {
                guard let textData = representation.textData, !textData.isEmpty else { return nil }
                return String(data: textData, encoding: .utf8)
            }()

            let data: Data? = {
                if let binaryData = representation.binaryData, !binaryData.isEmpty {
                    return binaryData
                }
                guard let assetRef = representation.assetRef else { return nil }
                return try? assetStore.load(
                    assetRef: assetRef,
                    fileExtension: representation.fileExtension
                )
            }()

            return ClipRepresentationPayload(
                kind: representation.kindValue,
                uti: representation.uti,
                text: text,
                data: data,
                fileExtension: representation.fileExtension,
                displayOrder: representation.displayOrder
            )
        }
    }
}

// SAFETY: ClipItemRepository is immutable after initialization. Core Data and file-system work is
// performed on the appropriate context queue via `performAndWaitThrowing`.
extension ClipItemRepository: @unchecked Sendable {}

extension ClipItemRepository: ClipItemRepositoryProtocol {}
