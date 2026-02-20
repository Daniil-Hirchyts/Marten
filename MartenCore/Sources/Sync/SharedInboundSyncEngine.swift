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

    public init(
        changesFetcher: ZoneChangesFetching,
        tokenManager: SyncTokenManager,
        persistenceController: PersistenceController,
        recordMapper: CloudRecordMapper,
        conflictResolver: ConflictResolver = ConflictResolver()
    ) {
        self.changesFetcher = changesFetcher
        self.tokenManager = tokenManager
        self.persistenceController = persistenceController
        self.recordMapper = recordMapper
        self.conflictResolver = conflictResolver
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

        var fetchedCount = 0
        var deletedCount = 0

        try context.performAndWait {
            try removeOrphanedLinkPreviews(in: context)
            if context.hasChanges {
                try context.save()
            }
        }

        do {
            let finalToken = try await changesFetcher.fetchChanges(
                zoneID: zoneID,
                previousServerChangeTokenData: previousTokenData,
                recordChanged: { record in
                    try context.performAndWait {
                        try self.applyRecord(record, in: context)
                        try self.removeOrphanedLinkPreviews(in: context)
                        fetchedCount += 1
                        if context.hasChanges {
                            try context.save()
                        }
                    }
                },
                recordDeleted: { recordID, recordType in
                    try context.performAndWait {
                        self.applyDeletion(recordID: recordID, recordType: recordType, in: context)
                        try self.removeOrphanedLinkPreviews(in: context)
                        deletedCount += 1
                        if context.hasChanges {
                            try context.save()
                        }
                    }
                },
                tokenUpdated: { tokenData in
                    try tokenStore.save(tokenData)
                }
            )

            if let tokenToPersist = finalToken {
                try tokenStore.save(tokenToPersist)
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            try tokenStore.clear()
            return try await syncZone(zoneID)
        }

        return InboundSyncResult(
            fetchedRecordCount: fetchedCount,
            deletedRecordCount: deletedCount,
            didFullResync: previousTokenData == nil
        )
    }

    private func applyRecord(_ record: CKRecord, in context: NSManagedObjectContext) throws {
        guard let type = record.cloudRecordType else { return }

        switch type {
        case .clipItem:
            guard let id = record.uuid(for: ClipItemField.id.rawValue) else { return }
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                try recordMapper.updateEntity(existing, from: record)
            } else {
                _ = try recordMapper.createClipItem(from: record, in: context)
            }

        case .pinboard:
            if record.bool(for: PinboardField.isSystemMarten.rawValue) {
                return
            }
            guard let id = record.uuid(for: PinboardField.id.rawValue) else { return }
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                try recordMapper.updateEntity(existing, from: record)
            } else {
                _ = try recordMapper.createPinboard(from: record, in: context)
            }

        case .clipRepresentation:
            guard let parentID = recordMapper.extractParentClipItemID(from: record) else { return }
            let parentRequest = ClipItem.fetchRequest()
            parentRequest.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentRequest.fetchLimit = 1
            guard let parent = try context.fetch(parentRequest).first else { return }

            guard let id = record.uuid(for: ClipRepresentationField.id.rawValue) else { return }
            let repRequest = ClipRepresentation.fetchRequest()
            repRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            repRequest.fetchLimit = 1
            if let existing = try context.fetch(repRequest).first {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
            } else {
                let rep = try recordMapper.createClipRepresentation(from: record, in: context)
                rep.clipItem = parent
                parent.addToRepresentations(rep)
            }

        case .linkPreview:
            guard let parentID = recordMapper.extractParentClipItemID(from: record) else { return }
            let parentRequest = ClipItem.fetchRequest()
            parentRequest.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentRequest.fetchLimit = 1
            guard let parent = try context.fetch(parentRequest).first else { return }

            guard let id = record.uuid(for: LinkPreviewField.id.rawValue) else { return }
            let lpRequest = LinkPreview.fetchRequest()
            lpRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            lpRequest.fetchLimit = 1
            if let existing = try context.fetch(lpRequest).first {
                try recordMapper.updateEntity(existing, from: record)
                existing.clipItem = parent
                parent.linkPreview = existing
            } else {
                let preview = try recordMapper.createLinkPreview(from: record, in: context)
                preview.clipItem = parent
                parent.linkPreview = preview
            }

        case .pinboardMembership:
            let membership = try recordMapper.createPinboardMembershipData(from: record)
            let itemRequest = ClipItem.fetchRequest()
            itemRequest.predicate = NSPredicate(format: "id == %@", membership.clipItemID as CVarArg)
            itemRequest.fetchLimit = 1
            guard let item = try context.fetch(itemRequest).first else { return }

            let pbRequest = Pinboard.fetchRequest()
            pbRequest.predicate = NSPredicate(format: "id == %@", membership.pinboardID as CVarArg)
            pbRequest.fetchLimit = 1
            guard let pinboard = try context.fetch(pbRequest).first else { return }
            guard !pinboard.isSystemMarten else { return }

            if !(pinboard.items?.contains(item) ?? false) {
                pinboard.addToItems(item)
            }
        }
    }

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
