import CloudKit
import CoreData
import Foundation

public struct InboundSyncResult: Equatable, Sendable {
    public let fetchedRecordCount: Int
    public let deletedRecordCount: Int
    public let didFullResync: Bool

    public init(fetchedRecordCount: Int, deletedRecordCount: Int, didFullResync: Bool) {
        self.fetchedRecordCount = fetchedRecordCount
        self.deletedRecordCount = deletedRecordCount
        self.didFullResync = didFullResync
    }
}

public protocol ZoneChangeTokenStoring: Sendable {
    func load() throws -> Data?
    func save(_ tokenData: Data) throws
    func clear() throws
}

// SAFETY: SyncTokenZoneStore is immutable after initialization and delegates all mutable state to
// SyncTokenManager, which internally synchronizes access.
public final class SyncTokenZoneStore: ZoneChangeTokenStoring, @unchecked Sendable {
    private let tokenManager: SyncTokenManager
    private let zoneID: CKRecordZone.ID

    public init(tokenManager: SyncTokenManager, zoneID: CKRecordZone.ID) {
        self.tokenManager = tokenManager
        self.zoneID = zoneID
    }

    public func load() throws -> Data? {
        guard let token = try tokenManager.loadToken(for: zoneID) else { return nil }
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        } catch {
            throw SyncTokenError.persistenceFailed(error)
        }
    }

    public func save(_ tokenData: Data) throws {
        do {
            let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
            guard let token else {
                throw SyncTokenError.invalidTokenFormat
            }
            try tokenManager.saveToken(token, for: zoneID)
        } catch let error as SyncTokenError {
            throw error
        } catch {
            throw SyncTokenError.decodingFailed(error)
        }
    }

    public func clear() throws {
        try tokenManager.clearToken(for: zoneID)
    }
}

public protocol ZoneChangesFetching: Sendable {
    func fetchChanges(
        zoneID: CKRecordZone.ID,
        previousServerChangeTokenData: Data?,
        recordChanged: @escaping (CKRecord) throws -> Void,
        recordDeleted: @escaping (CKRecord.ID, String) throws -> Void,
        tokenUpdated: @escaping (Data) throws -> Void
    ) async throws -> Data?
}

private struct InboundSyncTimeoutError: LocalizedError, Sendable {
    let timeoutSeconds: TimeInterval

    var errorDescription: String? {
        "CloudKit fetch timed out after \(String(format: "%.1f", timeoutSeconds)) seconds."
    }
}

// SAFETY: CKDatabase operations are expected to be thread-safe; this wrapper holds no mutable state
// beyond its immutable configuration.
public final class CloudKitZoneChangesFetcher: ZoneChangesFetching, @unchecked Sendable {
    private let database: CKDatabase
    private let resultsLimit: Int
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval

    public init(
        database: CKDatabase,
        resultsLimit: Int = 200,
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 120
    ) {
        self.database = database
        self.resultsLimit = resultsLimit
        self.requestTimeout = max(1, requestTimeout)
        self.resourceTimeout = max(self.requestTimeout, resourceTimeout)
    }

    public func fetchChanges(
        zoneID: CKRecordZone.ID,
        previousServerChangeTokenData: Data?,
        recordChanged: @escaping (CKRecord) throws -> Void,
        recordDeleted: @escaping (CKRecord.ID, String) throws -> Void,
        tokenUpdated: @escaping (Data) throws -> Void
    ) async throws -> Data? {
        let previousToken: CKServerChangeToken?
        if let previousServerChangeTokenData {
            do {
                previousToken = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: CKServerChangeToken.self,
                    from: previousServerChangeTokenData
                )
            } catch {
                throw SyncTokenError.decodingFailed(error)
            }
        } else {
            previousToken = nil
        }

        let operation = CKFetchRecordZoneChangesOperation()
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = previousToken
        configuration.resultsLimit = resultsLimit

        let operationConfiguration = CKOperation.Configuration()
        operationConfiguration.timeoutIntervalForRequest = requestTimeout
        operationConfiguration.timeoutIntervalForResource = resourceTimeout

        operation.recordZoneIDs = [zoneID]
        operation.configurationsByRecordZoneID = [zoneID: configuration]
        operation.configuration = operationConfiguration

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let continuationLock = NSLock()
                var didResume = false

                func finish(_ result: Result<Data?, Error>) {
                    continuationLock.lock()
                    defer { continuationLock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    if case .failure = result {
                        operation.cancel()
                    }
                    continuation.resume(with: result)
                }

                operation.recordWasChangedBlock = { _, result in
                    do {
                        let record = try result.get()
                        try recordChanged(record)
                    } catch {
                        finish(.failure(error))
                    }
                }

                operation.recordWithIDWasDeletedBlock = { recordID, recordType in
                    do {
                        try recordDeleted(recordID, recordType)
                    } catch {
                        finish(.failure(error))
                    }
                }

                operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                    guard let token else { return }
                    do {
                        let data = try NSKeyedArchiver.archivedData(
                            withRootObject: token,
                            requiringSecureCoding: true
                        )
                        try tokenUpdated(data)
                    } catch {
                        finish(.failure(error))
                    }
                }

                operation.recordZoneFetchResultBlock = { _, result in
                    switch result {
                    case .success(let zoneResult):
                        do {
                            let data = try NSKeyedArchiver.archivedData(
                                withRootObject: zoneResult.serverChangeToken,
                                requiringSecureCoding: true
                            )
                            finish(.success(data))
                        } catch {
                            finish(.failure(SyncTokenError.persistenceFailed(error)))
                        }
                    case .failure(let error):
                        finish(.failure(error))
                    }
                }

                database.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

/// Immutable dependencies are set during initialization; sync state is method-local.
public final class InboundSyncEngine: @unchecked Sendable {
    private let zoneID: CKRecordZone.ID
    private let changesFetcher: ZoneChangesFetching
    private let tokenStore: ZoneChangeTokenStoring
    private let persistenceController: PersistenceController
    private let recordMapper: CloudRecordMapper
    private let conflictResolver: ConflictResolver

    private let applyBatchSize: Int
    private let fetchTimeout: TimeInterval

    public init(
        zoneID: CKRecordZone.ID,
        changesFetcher: ZoneChangesFetching,
        tokenStore: ZoneChangeTokenStoring,
        persistenceController: PersistenceController,
        recordMapper: CloudRecordMapper,
        conflictResolver: ConflictResolver = ConflictResolver(),
        applyBatchSize: Int = 100,
        fetchTimeout: TimeInterval = 30
    ) {
        self.zoneID = zoneID
        self.changesFetcher = changesFetcher
        self.tokenStore = tokenStore
        self.persistenceController = persistenceController
        self.recordMapper = recordMapper
        self.conflictResolver = conflictResolver
        self.applyBatchSize = max(1, applyBatchSize)
        self.fetchTimeout = max(0.1, fetchTimeout)
    }

    public func syncInbound() async throws -> InboundSyncResult {
        try await syncInboundInternal(allowTokenReset: true)
    }

    private func syncInboundInternal(allowTokenReset: Bool) async throws -> InboundSyncResult {
        let previousTokenData = try tokenStore.load()
        let context = persistenceController.newBackgroundContext()
        context.transactionAuthor = "private-inbound-sync"

        var pendingRecords: [CKRecord] = []
        var pendingDeletions: [(CKRecord.ID, String)] = []
        var deferredRecords: [CKRecord] = []
        var deferredMemberships: [CKRecord] = []

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
                    in: context
                )
                try removeOrphanedLinkPreviews(in: context)

                if context.hasChanges {
                    try context.save()
                }
            }
        }

        do {
            let finalToken = try await withFetchTimeout { [self] in
                try await self.changesFetcher.fetchChanges(
                    zoneID: self.zoneID,
                    previousServerChangeTokenData: previousTokenData,
                    recordChanged: { record in
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
            }

            try applyPendingIfNeeded(force: true)
            if !deferredRecords.isEmpty || !deferredMemberships.isEmpty {
                try context.performAndWait {
                    try applyDeferredRecords(
                        records: &deferredRecords,
                        memberships: &deferredMemberships,
                        in: context
                    )
                    try removeOrphanedLinkPreviews(in: context)
                    if context.hasChanges {
                        try context.save()
                    }
                }
            }

            if let tokenToPersist = finalToken ?? lastUpdatedTokenData {
                try tokenStore.save(tokenToPersist)
            }

            return InboundSyncResult(
                fetchedRecordCount: fetchedCount,
                deletedRecordCount: deletedCount,
                didFullResync: previousTokenData == nil
            )
        } catch {
            if allowTokenReset, let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                try tokenStore.clear()
                return try await syncInboundInternal(allowTokenReset: false)
            }
            throw error
        }
    }

    private func withFetchTimeout<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let timeout = fetchTimeout
        guard timeout > 0 else { return try await operation() }

        let timeoutNanos = UInt64((timeout * 1_000_000_000).rounded())

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw CloudKitSyncError.fetchChangesFailed(
                    InboundSyncTimeoutError(timeoutSeconds: timeout)
                )
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw CloudKitSyncError.fetchChangesFailed(
                    InboundSyncTimeoutError(timeoutSeconds: timeout)
                )
            }

            return result
        }
    }

    private func applyChanges(
        records: [CKRecord],
        deletions: [(CKRecord.ID, String)],
        deferredRecords: inout [CKRecord],
        deferredMemberships: inout [CKRecord],
        in context: NSManagedObjectContext
    ) throws {
        var cache = buildCache(for: records, deletions: deletions, in: context)

        for (recordID, recordType) in deletions {
            try applyDeletion(recordID: recordID, recordType: recordType, cache: &cache, in: context)
        }

        let classified = classify(records)

        for record in classified.primary {
            try applyRecord(record, cache: &cache, in: context)
        }

        for record in classified.children {
            if try applyChildRecord(record, cache: &cache, in: context) == false {
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
        in context: NSManagedObjectContext
    ) throws {
        if !records.isEmpty {
            var stillDeferred: [CKRecord] = []
            for record in records {
                if try applyDeferredChildRecord(record, in: context) == false {
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

    private func applyDeferredChildRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws -> Bool {
        guard let type = record.cloudRecordType else { return true }

        switch type {
        case .clipRepresentation:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = fetchClipItem(id: parentID, in: context) else {
                return false
            }
            guard let id = record.uuid(for: ClipRepresentationField.id.rawValue) else { return true }

            if let existing = fetchClipRepresentation(id: id, in: context) {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
            } else {
                let rep = try recordMapper.createClipRepresentation(from: record, in: context)
                rep.clipItem = parent
                parent.addToRepresentations(rep)
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

    private struct ClassifiedRecords {
        let primary: [CKRecord]
        let children: [CKRecord]
        let memberships: [CKRecord]
    }

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

    private func applyChildRecord(_ record: CKRecord, cache: inout EntityCache, in context: NSManagedObjectContext) throws -> Bool {
        guard let type = record.cloudRecordType else { return true }

        switch type {
        case .clipRepresentation:
            guard let parentID = recordMapper.extractParentClipItemID(from: record),
                  let parent = cache.clipItems[parentID] else {
                return false
            }
            guard let id = record.uuid(for: ClipRepresentationField.id.rawValue) else { return true }

            if let existing = cache.clipRepresentations[id] {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
            } else {
                let rep = try recordMapper.createClipRepresentation(from: record, in: context)
                rep.clipItem = parent
                parent.addToRepresentations(rep)
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

    private func applyDeletion(recordID: CKRecord.ID, recordType: String, cache: inout EntityCache, in context: NSManagedObjectContext) throws {
        guard let cloudType = CloudRecordType(rawValue: recordType) else { return }

        guard let uuid = recordID.extractUUID() else { return }
        switch cloudType {
        case .clipItem:
            if let existing = cache.clipItems[uuid] {
                context.delete(existing)
                cache.clipItems.removeValue(forKey: uuid)
                if !existing.contentHash.isEmpty {
                    cache.clipItemsByHash.removeValue(forKey: existing.contentHash)
                }
            }
        case .clipRepresentation:
            if let existing = cache.clipRepresentations[uuid] {
                context.delete(existing)
                cache.clipRepresentations.removeValue(forKey: uuid)
            }
        case .pinboard:
            if let existing = cache.pinboards[uuid] {
                if existing.isSystemMarten {
                    return
                }
                context.delete(existing)
                cache.pinboards.removeValue(forKey: uuid)
            }
        case .linkPreview:
            if let existing = cache.linkPreviews[uuid] {
                context.delete(existing)
                cache.linkPreviews.removeValue(forKey: uuid)
            }
        case .pinboardMembership:
            removeMembership(membershipID: uuid, in: context)
        }
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

    private func fetchClipItem(id: UUID, in context: NSManagedObjectContext) -> ClipItem? {
        let request = ClipItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func fetchClipItem(contentHash: String, in context: NSManagedObjectContext) -> ClipItem? {
        let request = ClipItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "contentHash == %@", contentHash)
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

    private func removeOrphanedLinkPreviews(in context: NSManagedObjectContext) throws {
        let request = LinkPreview.fetchRequest()
        request.predicate = NSPredicate(format: "clipItem == nil")

        let orphans = try context.fetch(request)
        guard !orphans.isEmpty else { return }

        for orphan in orphans {
            context.delete(orphan)
        }
    }

    private func removeMembership(membershipID: UUID, in context: NSManagedObjectContext) {
        let request = ClipItem.fetchRequest()
        request.relationshipKeyPathsForPrefetching = ["pinboards"]

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
}
