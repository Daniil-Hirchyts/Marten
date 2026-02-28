import CloudKit
import CoreData
import Foundation

/// Handles inbound sync from the shared CloudKit database.
///
/// Mirrors InboundSyncEngine structure but operates across multiple shared zones.
/// Sets `transactionAuthor = "shared-inbound-sync"` to prevent outbound sync loops.
public final class SharedInboundSyncEngine: @unchecked Sendable {
    private let changesFetcher: ZoneChangesFetching
    private let tokenManager: SyncTokenManager
    private let persistenceController: PersistenceController
    private let recordMapper: CloudRecordMapper
    private let conflictResolver: ConflictResolver
    private let assetSyncManager: AssetSyncManager
    private let applyBatchSize: Int

    public init(
        changesFetcher: ZoneChangesFetching,
        tokenManager: SyncTokenManager,
        persistenceController: PersistenceController,
        recordMapper: CloudRecordMapper,
        assetSyncManager: AssetSyncManager = AssetSyncManager(),
        conflictResolver: ConflictResolver = ConflictResolver(),
        applyBatchSize: Int = 100
    ) {
        self.changesFetcher = changesFetcher
        self.tokenManager = tokenManager
        self.persistenceController = persistenceController
        self.recordMapper = recordMapper
        self.assetSyncManager = assetSyncManager
        self.conflictResolver = conflictResolver
        self.applyBatchSize = max(1, applyBatchSize)
    }

    /// Syncs all known shared zones.
    ///
    /// - Parameter zoneIDs: The shared zone IDs to sync.
    /// - Returns: Total records fetched and deleted across all zones.
    public func syncInbound(zoneIDs: [CKRecordZone.ID]) async throws -> InboundSyncResult {
        var totalFetched = 0
        var totalDeleted = 0

        for zoneID in zoneIDs {
            let result = try await syncZone(zoneID)
            totalFetched += result.fetchedRecordCount
            totalDeleted += result.deletedRecordCount
        }

        return InboundSyncResult(
            fetchedRecordCount: totalFetched,
            deletedRecordCount: totalDeleted,
            didFullResync: false
        )
    }

    private func syncZone(_ zoneID: CKRecordZone.ID) async throws -> InboundSyncResult {
        let tokenStore = SyncTokenZoneStore(tokenManager: tokenManager, zoneID: zoneID)
        let previousTokenData = try tokenStore.load()
        let context = persistenceController.newBackgroundContext()
        context.transactionAuthor = SyncTransactionAuthor.sharedInbound

        var pendingRecords: [CKRecord] = []
        var pendingDeletions: [(CKRecord.ID, String)] = []
        var deferredRecords: [CKRecord] = []
        var deferredMemberships: [CKRecord] = []
        var preloadedAssets: [CKRecord.ID: AssetSyncManager.PreloadedAsset] = [:]

        var fetchedCount = 0
        var deletedCount = 0
        var lastUpdatedTokenData: Data?

        try context.performAndWait {
            try removeOrphanedLinkPreviews(in: context)
            if context.hasChanges {
                try context.save()
            }
        }

        func applyPendingIfNeeded(force: Bool) throws {
            guard force || pendingRecords.count + pendingDeletions.count >= applyBatchSize else { return }

            let recordsToApply = pendingRecords
            let deletionsToApply = pendingDeletions
            pendingRecords.removeAll(keepingCapacity: true)
            pendingDeletions.removeAll(keepingCapacity: true)

            try context.performAndWait {
                try applyChanges(
                    records: recordsToApply,
                    deletions: deletionsToApply,
                    deferredRecords: &deferredRecords,
                    deferredMemberships: &deferredMemberships,
                    preloadedAssets: preloadedAssets,
                    in: context
                )
                try removeOrphanedLinkPreviews(in: context)
                if context.hasChanges {
                    try context.save()
                }
            }
        }

        do {
            let finalToken = try await changesFetcher.fetchChanges(
                zoneID: zoneID,
                previousServerChangeTokenData: previousTokenData,
                recordChanged: { record in
                    if record.cloudRecordType == .clipRepresentation,
                       let asset = record.asset(for: ClipRepresentationField.asset.rawValue),
                       let fileURL = asset.fileURL,
                       let data = try? Data(contentsOf: fileURL)
                    {
                        let ext = fileURL.pathExtension
                        preloadedAssets[record.recordID] = AssetSyncManager.PreloadedAsset(
                            data: data,
                            fileExtension: ext.isEmpty ? nil : ext
                        )
                    }
                    pendingRecords.append(record)
                    fetchedCount += 1
                    try applyPendingIfNeeded(force: false)
                },
                recordDeleted: { recordID, recordType in
                    pendingDeletions.append((recordID, recordType))
                    deletedCount += 1
                    try applyPendingIfNeeded(force: false)
                },
                tokenUpdated: { tokenData in
                    lastUpdatedTokenData = tokenData
                }
            )

            try applyPendingIfNeeded(force: true)
            if !deferredRecords.isEmpty || !deferredMemberships.isEmpty {
                try context.performAndWait {
                    try applyDeferredRecords(
                        records: &deferredRecords,
                        memberships: &deferredMemberships,
                        preloadedAssets: preloadedAssets,
                        in: context
                    )
                    try removeOrphanedLinkPreviews(in: context)
                    if context.hasChanges {
                        try context.save()
                    }
                }
            }

            let hasUnresolvedDeferredRecords = !deferredRecords.isEmpty || !deferredMemberships.isEmpty

            if !hasUnresolvedDeferredRecords,
               let tokenToPersist = finalToken ?? lastUpdatedTokenData {
                try tokenStore.save(tokenToPersist)
            }
        } catch let error as CKError {
            switch error.code {
            case .changeTokenExpired:
                try tokenStore.clear()
                return try await syncZone(zoneID)
            case .zoneNotFound, .userDeletedZone:
                try tokenStore.clear()
                throw CloudKitErrorClassifier.classify(error)
            default:
                throw error
            }
        }

        return InboundSyncResult(
            fetchedRecordCount: fetchedCount,
            deletedRecordCount: deletedCount,
            didFullResync: previousTokenData == nil
        )
    }

    // MARK: - Three-Phase Apply

    private func applyChanges(
        records: [CKRecord],
        deletions: [(CKRecord.ID, String)],
        deferredRecords: inout [CKRecord],
        deferredMemberships: inout [CKRecord],
        preloadedAssets: [CKRecord.ID: AssetSyncManager.PreloadedAsset],
        in context: NSManagedObjectContext
    ) throws {
        var cache = buildCache(for: records, deletions: deletions, in: context)

        for (recordID, recordType) in deletions {
            applyDeletion(recordID: recordID, recordType: recordType, in: context)
        }

        let classified = classify(records)

        for record in classified.primary {
            try applyRecord(record, cache: &cache, in: context)
        }

        for record in classified.children {
            if try applyChildRecord(record, cache: &cache, preloadedAssets: preloadedAssets, in: context) == false {
                deferredRecords.append(record)
            }
        }

        for record in classified.memberships {
            if try applyMembershipRecord(record, cache: &cache, in: context) == false {
                deferredMemberships.append(record)
            }
        }
    }

    private func applyDeferredRecords(
        records: inout [CKRecord],
        memberships: inout [CKRecord],
        preloadedAssets: [CKRecord.ID: AssetSyncManager.PreloadedAsset],
        in context: NSManagedObjectContext
    ) throws {
        if !records.isEmpty {
            var stillDeferred: [CKRecord] = []
            for record in records {
                if try applyDeferredChildRecord(record, preloadedAssets: preloadedAssets, in: context) == false {
                    stillDeferred.append(record)
                }
            }
            records = stillDeferred
        }

        if !memberships.isEmpty {
            var stillDeferred: [CKRecord] = []
            for record in memberships {
                if try applyDeferredMembershipRecord(record, in: context) == false {
                    stillDeferred.append(record)
                }
            }
            memberships = stillDeferred
        }
    }

    // MARK: - Classification

    private struct ClassifiedRecords {
        let primary: [CKRecord]
        let children: [CKRecord]
        let memberships: [CKRecord]
    }

    private func classify(_ records: [CKRecord]) -> ClassifiedRecords {
        var primary: [CKRecord] = []
        var children: [CKRecord] = []
        var memberships: [CKRecord] = []

        for record in records {
            guard let type = record.cloudRecordType else { continue }
            switch type {
            case .clipItem, .pinboard:
                primary.append(record)
            case .clipRepresentation, .linkPreview:
                children.append(record)
            case .pinboardMembership:
                memberships.append(record)
            }
        }

        return ClassifiedRecords(primary: primary, children: children, memberships: memberships)
    }

    // MARK: - Entity Cache

    private struct EntityCache {
        var clipItems: [UUID: ClipItem]
        var clipRepresentations: [UUID: ClipRepresentation]
        var pinboards: [UUID: Pinboard]
        var linkPreviews: [UUID: LinkPreview]
        var clipItemsByHash: [String: ClipItem]

        mutating func insert(_ item: ClipItem) {
            clipItems[item.id] = item
            if !item.contentHash.isEmpty {
                clipItemsByHash[item.contentHash] = item
            }
        }

        mutating func insert(_ rep: ClipRepresentation) {
            clipRepresentations[rep.id] = rep
        }

        mutating func insert(_ pb: Pinboard) {
            pinboards[pb.id] = pb
        }

        mutating func insert(_ lp: LinkPreview) {
            linkPreviews[lp.id] = lp
        }
    }

    // MARK: - Primary Record Handlers

    private func applyRecord(_ record: CKRecord, cache: inout EntityCache, in context: NSManagedObjectContext) throws {
        guard let type = record.cloudRecordType else { return }

        switch type {
        case .clipItem:
            guard let id = record.uuid(for: ClipItemField.id.rawValue) else { return }
            if let existing = cache.clipItems[id] {
                try recordMapper.updateEntity(existing, from: record)
            } else if let contentHash = record.string(for: ClipItemField.contentHash.rawValue),
                      !contentHash.isEmpty,
                      let existingByHash = cache.clipItemsByHash[contentHash] {
                let localRecord = recordMapper.mapToRecord(existingByHash)
                switch conflictResolver.resolveClipItemAppendOnly(local: localRecord, remote: record) {
                case .keepLocal:
                    break
                case .keepRemote:
                    try recordMapper.updateEntity(existingByHash, from: record)
                }
            } else {
                let newItem = try recordMapper.createClipItem(from: record, in: context)
                cache.insert(newItem)
            }

        case .pinboard:
            if record.bool(for: PinboardField.isSystemMarten.rawValue) {
                return
            }
            guard let id = record.uuid(for: PinboardField.id.rawValue) else { return }
            if let existing = cache.pinboards[id] {
                try recordMapper.updateEntity(existing, from: record)
            } else {
                let newPinboard = try recordMapper.createPinboard(from: record, in: context)
                cache.insert(newPinboard)
            }

        case .clipRepresentation, .pinboardMembership, .linkPreview:
            return
        }
    }

    // MARK: - Child Record Handlers

    private func applyChildRecord(
        _ record: CKRecord,
        cache: inout EntityCache,
        preloadedAssets: [CKRecord.ID: AssetSyncManager.PreloadedAsset],
        in context: NSManagedObjectContext
    ) throws -> Bool {
        guard let type = record.cloudRecordType else { return true }

        switch type {
        case .clipRepresentation:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = cache.clipItems[parentID] else {
                return false
            }
            guard let id = record.uuid(for: ClipRepresentationField.id.rawValue) else { return true }

            let preloaded = preloadedAssets[record.recordID]
            if let existing = cache.clipRepresentations[id] {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
                try assetSyncManager.applyDownloadedAssetIfPresentSync(from: record, to: existing, preloadedAssetData: preloaded)
            } else {
                let rep = try recordMapper.createClipRepresentation(from: record, in: context)
                rep.clipItem = parent
                parent.addToRepresentations(rep)
                try assetSyncManager.applyDownloadedAssetIfPresentSync(from: record, to: rep, preloadedAssetData: preloaded)
                cache.insert(rep)
            }
            return true

        case .linkPreview:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = cache.clipItems[parentID] else {
                return false
            }
            guard let id = record.uuid(for: LinkPreviewField.id.rawValue) else { return true }

            if let existing = cache.linkPreviews[id] {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
                parent.linkPreview = existing
            } else {
                let preview = try recordMapper.createLinkPreview(from: record, in: context)
                preview.clipItem = parent
                parent.linkPreview = preview
                cache.insert(preview)
            }
            return true

        case .clipItem, .pinboard, .pinboardMembership:
            return true
        }
    }

    private func applyDeferredChildRecord(
        _ record: CKRecord,
        preloadedAssets: [CKRecord.ID: AssetSyncManager.PreloadedAsset],
        in context: NSManagedObjectContext
    ) throws -> Bool {
        guard let type = record.cloudRecordType else { return true }

        switch type {
        case .clipRepresentation:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = fetchClipItem(id: parentID, in: context) else {
                return false
            }
            guard let id = record.uuid(for: ClipRepresentationField.id.rawValue) else { return true }

            let preloaded = preloadedAssets[record.recordID]
            if let existing = fetchClipRepresentation(id: id, in: context) {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
                try assetSyncManager.applyDownloadedAssetIfPresentSync(from: record, to: existing, preloadedAssetData: preloaded)
            } else {
                let rep = try recordMapper.createClipRepresentation(from: record, in: context)
                rep.clipItem = parent
                parent.addToRepresentations(rep)
                try assetSyncManager.applyDownloadedAssetIfPresentSync(from: record, to: rep, preloadedAssetData: preloaded)
            }
            return true

        case .linkPreview:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = fetchClipItem(id: parentID, in: context) else {
                return false
            }
            guard let id = record.uuid(for: LinkPreviewField.id.rawValue) else { return true }

            if let existing = fetchLinkPreview(id: id, in: context) {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
                parent.linkPreview = existing
            } else {
                let preview = try recordMapper.createLinkPreview(from: record, in: context)
                preview.clipItem = parent
                parent.linkPreview = preview
            }
            return true

        case .clipItem, .pinboard, .pinboardMembership:
            return true
        }
    }

    // MARK: - Membership Handlers

    private func applyMembershipRecord(_ record: CKRecord, cache: inout EntityCache, in context: NSManagedObjectContext) throws -> Bool {
        guard record.cloudRecordType == .pinboardMembership else { return true }

        let membership = try recordMapper.createPinboardMembershipData(from: record)
        guard let item = cache.clipItems[membership.clipItemID],
              let pinboard = cache.pinboards[membership.pinboardID] else {
            return false
        }
        guard !pinboard.isSystemMarten else { return true }

        if !(pinboard.items?.contains(item) ?? false) {
            pinboard.addToItems(item)
        }
        return true
    }

    private func applyDeferredMembershipRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws -> Bool {
        guard record.cloudRecordType == .pinboardMembership else { return true }

        let membership = try recordMapper.createPinboardMembershipData(from: record)
        guard let item = fetchClipItem(id: membership.clipItemID, in: context),
              let pinboard = fetchPinboard(id: membership.pinboardID, in: context) else {
            return false
        }
        guard !pinboard.isSystemMarten else { return true }

        if !(pinboard.items?.contains(item) ?? false) {
            pinboard.addToItems(item)
        }
        return true
    }

    // MARK: - Deletion

    private func applyDeletion(
        recordID: CKRecord.ID,
        recordType: String,
        in context: NSManagedObjectContext
    ) {
        guard let cloudType = CloudRecordType(rawValue: recordType),
              let uuid = recordID.extractUUID() else { return }

        switch cloudType {
        case .clipItem:
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                context.delete(existing)
            }
        case .clipRepresentation:
            let request = ClipRepresentation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                context.delete(existing)
            }
        case .pinboard:
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                if existing.isSystemMarten {
                    return
                }
                context.delete(existing)
            }
        case .linkPreview:
            let request = LinkPreview.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                context.delete(existing)
            }
        case .pinboardMembership:
            removeMembership(membershipID: uuid, in: context)
        }
    }

    private func removeMembership(membershipID: UUID, in context: NSManagedObjectContext) {
        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "ANY pinboards.isSystemMarten == NO")
        request.relationshipKeyPathsForPrefetching = ["pinboards"]
        request.fetchBatchSize = 100

        guard let items = try? context.fetch(request) else { return }

        for item in items {
            let customPinboards = (item.pinboards ?? []).filter { !$0.isSystemMarten }
            for pinboard in customPinboards {
                let candidateID = CKRecord.ID.deterministicMembershipUUID(
                    clipItemID: item.id,
                    pinboardID: pinboard.id
                )
                if candidateID == membershipID {
                    item.removeFromPinboards(pinboard)
                    return
                }
            }
        }
    }

    // MARK: - Cache Building

    private func buildCache(for records: [CKRecord], deletions: [(CKRecord.ID, String)], in context: NSManagedObjectContext) -> EntityCache {
        var clipItemIDs = Set<UUID>()
        var clipRepIDs = Set<UUID>()
        var pinboardIDs = Set<UUID>()
        var linkPreviewIDs = Set<UUID>()
        var contentHashes = Set<String>()

        for record in records {
            guard let type = record.cloudRecordType else { continue }
            switch type {
            case .clipItem:
                if let id = record.uuid(for: ClipItemField.id.rawValue) { clipItemIDs.insert(id) }
                if let hash = record.string(for: ClipItemField.contentHash.rawValue), !hash.isEmpty { contentHashes.insert(hash) }
            case .clipRepresentation:
                if let id = record.uuid(for: ClipRepresentationField.id.rawValue) { clipRepIDs.insert(id) }
                if let parentID = recordMapper.extractParentClipItemID(from: record) { clipItemIDs.insert(parentID) }
            case .linkPreview:
                if let id = record.uuid(for: LinkPreviewField.id.rawValue) { linkPreviewIDs.insert(id) }
                if let parentID = recordMapper.extractParentClipItemID(from: record) { clipItemIDs.insert(parentID) }
            case .pinboard:
                if record.bool(for: PinboardField.isSystemMarten.rawValue) == false,
                   let id = record.uuid(for: PinboardField.id.rawValue)
                {
                    pinboardIDs.insert(id)
                }
            case .pinboardMembership:
                if let membership = try? recordMapper.createPinboardMembershipData(from: record) {
                    clipItemIDs.insert(membership.clipItemID)
                    pinboardIDs.insert(membership.pinboardID)
                }
            }
        }

        for (recordID, _) in deletions {
            if let uuid = recordID.extractUUID() {
                clipItemIDs.insert(uuid)
                clipRepIDs.insert(uuid)
                pinboardIDs.insert(uuid)
                linkPreviewIDs.insert(uuid)
            }
        }

        var cache = EntityCache(
            clipItems: batchFetchClipItems(ids: clipItemIDs, in: context),
            clipRepresentations: batchFetchClipRepresentations(ids: clipRepIDs, in: context),
            pinboards: batchFetchPinboards(ids: pinboardIDs, in: context),
            linkPreviews: batchFetchLinkPreviews(ids: linkPreviewIDs, in: context),
            clipItemsByHash: [:]
        )

        for item in cache.clipItems.values {
            if !item.contentHash.isEmpty {
                cache.clipItemsByHash[item.contentHash] = item
            }
        }

        let missingHashes = contentHashes.subtracting(Set(cache.clipItemsByHash.keys))
        if !missingHashes.isEmpty {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(format: "contentHash IN %@", missingHashes)
            if let items = try? context.fetch(request) {
                for item in items {
                    cache.clipItems[item.id] = item
                    cache.clipItemsByHash[item.contentHash] = item
                }
            }
        }

        return cache
    }

    private func batchFetchClipItems(ids: Set<UUID>, in context: NSManagedObjectContext) -> [UUID: ClipItem] {
        guard !ids.isEmpty else { return [:] }
        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let items = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func batchFetchClipRepresentations(ids: Set<UUID>, in context: NSManagedObjectContext) -> [UUID: ClipRepresentation] {
        guard !ids.isEmpty else { return [:] }
        let request = ClipRepresentation.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let items = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func batchFetchPinboards(ids: Set<UUID>, in context: NSManagedObjectContext) -> [UUID: Pinboard] {
        guard !ids.isEmpty else { return [:] }
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let items = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func batchFetchLinkPreviews(ids: Set<UUID>, in context: NSManagedObjectContext) -> [UUID: LinkPreview] {
        guard !ids.isEmpty else { return [:] }
        let request = LinkPreview.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let items = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    // MARK: - Point Fetches (for deferred pass)

    private func fetchClipItem(id: UUID, in context: NSManagedObjectContext) -> ClipItem? {
        let request = ClipItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchClipRepresentation(id: UUID, in context: NSManagedObjectContext) -> ClipRepresentation? {
        let request = ClipRepresentation.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchPinboard(id: UUID, in context: NSManagedObjectContext) -> Pinboard? {
        let request = Pinboard.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchLinkPreview(id: UUID, in context: NSManagedObjectContext) -> LinkPreview? {
        let request = LinkPreview.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    // MARK: - Orphan Cleanup

    private func removeOrphanedLinkPreviews(in context: NSManagedObjectContext) throws {
        let request = LinkPreview.fetchRequest()
        request.predicate = NSPredicate(format: "clipItem == nil")

        let orphans = try context.fetch(request)
        guard !orphans.isEmpty else { return }

        for orphan in orphans {
            context.delete(orphan)
        }
    }
}
