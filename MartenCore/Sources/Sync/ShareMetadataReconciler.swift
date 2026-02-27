import CloudKit
import CoreData
import Foundation

public struct ShareMetadataReconcileResult: Equatable {
    public let createdCount: Int
    public let updatedCount: Int
    public let removedCount: Int
    public let discoveredSharedZoneIDs: [CKRecordZone.ID]

    public init(
        createdCount: Int,
        updatedCount: Int,
        removedCount: Int,
        discoveredSharedZoneIDs: [CKRecordZone.ID]
    ) {
        self.createdCount = createdCount
        self.updatedCount = updatedCount
        self.removedCount = removedCount
        self.discoveredSharedZoneIDs = discoveredSharedZoneIDs
    }

    public static let empty = ShareMetadataReconcileResult(
        createdCount: 0,
        updatedCount: 0,
        removedCount: 0,
        discoveredSharedZoneIDs: []
    )
}

public final class ShareMetadataReconciler: @unchecked Sendable {
    public init() {}

    @discardableResult
    public func reconcile(
        persistenceController: PersistenceController
    ) throws -> ShareMetadataReconcileResult {
        let context = persistenceController.newBackgroundContext()

        var createdCount = 0
        var updatedCount = 0
        var removedCount = 0
        var discoveredZoneIDs = Set<CKRecordZone.ID>()

        try context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == NO")
            request.returnsObjectsAsFaults = false
            request.relationshipKeyPathsForPrefetching = ["shareMetadata"]
            let pinboards = try context.fetch(request)

            for pinboard in pinboards {
                let rawToken = pinboard.shareToken?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let rawToken, !rawToken.isEmpty else {
                    if let existing = pinboard.shareMetadata {
                        context.delete(existing)
                        removedCount += 1
                    }
                    pinboard.shareToken = nil
                    continue
                }

                guard let envelope = ShareTokenEnvelope.decode(from: rawToken) else {
                    pinboard.shareToken = nil
                    if let existing = pinboard.shareMetadata {
                        context.delete(existing)
                        removedCount += 1
                    }
                    continue
                }

                // Keep serialized tokens normalized to avoid drift across platforms.
                if let normalized = envelope.encodedString(), normalized != pinboard.shareToken {
                    pinboard.shareToken = normalized
                }

                if let existing = pinboard.shareMetadata {
                    let previousZoneName = existing.zoneName
                    let previousZoneOwnerName = existing.zoneOwnerName
                    let previousIsOwner = existing.isOwner

                    if apply(envelope: envelope, to: existing) {
                        updatedCount += 1
                        if envelope.isOwner == false
                            && (
                                previousZoneName != envelope.zoneName
                                    || previousZoneOwnerName != envelope.zoneOwnerName
                                    || previousIsOwner != envelope.isOwner
                            )
                        {
                            discoveredZoneIDs.insert(envelope.zoneID)
                        }
                    }
                } else {
                    guard let metadata = NSEntityDescription.insertNewObject(
                        forEntityName: "ShareMetadata",
                        into: context
                    ) as? ShareMetadata else {
                        throw PinboardSharingError.invalidShareMetadata
                    }

                    metadata.id = UUID()
                    _ = apply(envelope: envelope, to: metadata)
                    metadata.pinboard = pinboard
                    createdCount += 1
                    if envelope.isOwner == false {
                        discoveredZoneIDs.insert(envelope.zoneID)
                    }
                }
            }

            if context.hasChanges {
                try context.save()
            }
        }

        return ShareMetadataReconcileResult(
            createdCount: createdCount,
            updatedCount: updatedCount,
            removedCount: removedCount,
            discoveredSharedZoneIDs: discoveredZoneIDs.sorted {
                if $0.zoneName == $1.zoneName {
                    return $0.ownerName < $1.ownerName
                }
                return $0.zoneName < $1.zoneName
            }
        )
    }

    @discardableResult
    private func apply(envelope: ShareTokenEnvelope, to metadata: ShareMetadata) -> Bool {
        var didChange = false

        if metadata.shareRecordName != envelope.shareRecordName {
            metadata.shareRecordName = envelope.shareRecordName
            didChange = true
        }
        if metadata.rootRecordName != envelope.rootRecordName {
            metadata.rootRecordName = envelope.rootRecordName
            didChange = true
        }
        if metadata.zoneName != envelope.zoneName {
            metadata.zoneName = envelope.zoneName
            didChange = true
        }
        if metadata.zoneOwnerName != envelope.zoneOwnerName {
            metadata.zoneOwnerName = envelope.zoneOwnerName
            didChange = true
        }
        if metadata.isOwner != envelope.isOwner {
            metadata.isOwner = envelope.isOwner
            didChange = true
        }
        if metadata.accessControlRaw != envelope.accessControlRaw {
            metadata.accessControlRaw = envelope.accessControlRaw
            didChange = true
        }
        if metadata.defaultPermissionRaw != envelope.defaultPermissionRaw {
            metadata.defaultPermissionRaw = envelope.defaultPermissionRaw
            didChange = true
        }
        if metadata.shareURL != envelope.shareURL {
            metadata.shareURL = envelope.shareURL
            didChange = true
        }

        return didChange
    }
}
