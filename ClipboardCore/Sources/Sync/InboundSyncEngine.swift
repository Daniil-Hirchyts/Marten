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

// SAFETY: CKDatabase operations are expected to be thread-safe; this wrapper holds no mutable state
// beyond its immutable configuration.
public final class CloudKitZoneChangesFetcher: ZoneChangesFetching, @unchecked Sendable {
    private let database: CKDatabase
    private let resultsLimit: Int

    public init(database: CKDatabase, resultsLimit: Int = 200) {
        self.database = database
        self.resultsLimit = resultsLimit
    }

    public func fetchChanges(
        zoneID: CKRecordZone.ID,
        previousServerChangeTokenData: Data?,
        recordChanged: @escaping (CKRecord) throws -> Void,
        recordDeleted: @escaping (CKRecord.ID, String) throws -> Void,
        tokenUpdated: @escaping (Data) throws -> Void
    ) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            let previousToken: CKServerChangeToken?
            if let previousServerChangeTokenData {
                do {
                    previousToken = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: CKServerChangeToken.self,
                        from: previousServerChangeTokenData
                    )
                } catch {
                    continuation.resume(throwing: SyncTokenError.decodingFailed(error))
                    return
                }
            } else {
                previousToken = nil
            }

            let operation = CKFetchRecordZoneChangesOperation()
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = previousToken
            configuration.resultsLimit = resultsLimit

            operation.recordZoneIDs = [zoneID]
            operation.configurationsByRecordZoneID = [zoneID: configuration]

            operation.recordWasChangedBlock = { _, result in
                do {
                    let record = try result.get()
                    try recordChanged(record)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            operation.recordWithIDWasDeletedBlock = { recordID, recordType in
                do {
                    try recordDeleted(recordID, recordType)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                guard let token else { return }
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                    try tokenUpdated(data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let zoneResult):
                    do {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: zoneResult.serverChangeToken, requiringSecureCoding: true)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: SyncTokenError.persistenceFailed(error))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}

public final class InboundSyncEngine {
    private let zoneID: CKRecordZone.ID
    private let changesFetcher: ZoneChangesFetching
    private let tokenStore: ZoneChangeTokenStoring
    private let persistenceController: PersistenceController
    private let recordMapper: CloudRecordMapper
    private let conflictResolver: ConflictResolver

    private let applyBatchSize: Int

    public init(
        zoneID: CKRecordZone.ID,
        changesFetcher: ZoneChangesFetching,
        tokenStore: ZoneChangeTokenStoring,
        persistenceController: PersistenceController,
        recordMapper: CloudRecordMapper,
        conflictResolver: ConflictResolver = ConflictResolver(),
        applyBatchSize: Int = 100
    ) {
        self.zoneID = zoneID
        self.changesFetcher = changesFetcher
        self.tokenStore = tokenStore
        self.persistenceController = persistenceController
        self.recordMapper = recordMapper
        self.conflictResolver = conflictResolver
        self.applyBatchSize = max(1, applyBatchSize)
    }

    public func syncInbound() async throws -> InboundSyncResult {
        try await syncInboundInternal(allowTokenReset: true)
    }

    private func syncInboundInternal(allowTokenReset: Bool) async throws -> InboundSyncResult {
        let previousTokenData = try tokenStore.load()
        let context = persistenceController.newBackgroundContext()

        var pendingRecords: [CKRecord] = []
        var pendingDeletions: [(CKRecord.ID, String)] = []
        var deferredRecords: [CKRecord] = []
        var deferredMemberships: [CKRecord] = []

        var fetchedCount = 0
        var deletedCount = 0
        var lastUpdatedTokenData: Data?

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
                        in: context
                    )
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

    private func applyChanges(
        records: [CKRecord],
        deletions: [(CKRecord.ID, String)],
        deferredRecords: inout [CKRecord],
        deferredMemberships: inout [CKRecord],
        in context: NSManagedObjectContext
    ) throws {
        for (recordID, recordType) in deletions {
            try applyDeletion(recordID: recordID, recordType: recordType, in: context)
        }

        let classified = classify(records)

        for record in classified.primary {
            try applyRecord(record, in: context)
        }

        for record in classified.children {
            if try applyChildRecord(record, in: context) == false {
                deferredRecords.append(record)
            }
        }

        for record in classified.memberships {
            if try applyMembershipRecord(record, in: context) == false {
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
                if try applyChildRecord(record, in: context) == false {
                    stillDeferred.append(record)
                }
            }
            records = stillDeferred
        }

        if !memberships.isEmpty {
            var stillDeferred: [CKRecord] = []
            for record in memberships {
                if try applyMembershipRecord(record, in: context) == false {
                    stillDeferred.append(record)
                }
            }
            memberships = stillDeferred
        }
    }

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

    private func applyRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws {
        guard let type = record.cloudRecordType else { return }

        switch type {
        case .clipItem:
            guard let id = record.uuid(for: ClipItemField.id.rawValue) else { return }
            if let existing = fetchClipItem(id: id, in: context) {
                try recordMapper.updateEntity(existing, from: record)
            } else if let contentHash = record.string(for: ClipItemField.contentHash.rawValue),
                      let existingByHash = fetchClipItem(contentHash: contentHash, in: context) {
                let localRecord = recordMapper.mapToRecord(existingByHash)
                switch conflictResolver.resolveClipItemAppendOnly(local: localRecord, remote: record) {
                case .keepLocal:
                    break
                case .keepRemote:
                    try recordMapper.updateEntity(existingByHash, from: record)
                }
            } else {
                _ = try recordMapper.createClipItem(from: record, in: context)
            }

        case .pinboard:
            guard let id = record.uuid(for: PinboardField.id.rawValue) else { return }
            if let existing = fetchPinboard(id: id, in: context) {
                try recordMapper.updateEntity(existing, from: record)
            } else {
                _ = try recordMapper.createPinboard(from: record, in: context)
            }

        case .clipRepresentation, .pinboardMembership, .linkPreview:
            return
        }
    }

    private func applyChildRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws -> Bool {
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

    private func applyMembershipRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws -> Bool {
        guard record.cloudRecordType == .pinboardMembership else { return true }

        let membership = try recordMapper.createPinboardMembershipData(from: record)
        guard let item = fetchClipItem(id: membership.clipItemID, in: context),
              let pinboard = fetchPinboard(id: membership.pinboardID, in: context) else {
            return false
        }

        if !(pinboard.items?.contains(item) ?? false) {
            pinboard.addToItems(item)
        }
        return true
    }

    private func applyDeletion(recordID: CKRecord.ID, recordType: String, in context: NSManagedObjectContext) throws {
        guard let cloudType = CloudRecordType(rawValue: recordType) else { return }

        guard let uuid = recordID.extractUUID() else { return }
        switch cloudType {
        case .clipItem:
            if let existing = fetchClipItem(id: uuid, in: context) {
                context.delete(existing)
            }
        case .clipRepresentation:
            if let existing = fetchClipRepresentation(id: uuid, in: context) {
                context.delete(existing)
            }
        case .pinboard:
            if let existing = fetchPinboard(id: uuid, in: context) {
                context.delete(existing)
            }
        case .linkPreview:
            if let existing = fetchLinkPreview(id: uuid, in: context) {
                context.delete(existing)
            }
        case .pinboardMembership:
            return
        }
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
}
