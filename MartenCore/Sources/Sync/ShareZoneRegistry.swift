import CloudKit
import CoreData
import Foundation

/// Identifies which CloudKit database to target.
public enum SyncDatabase: Equatable, Sendable {
    case privateDB
    case sharedDB
}

/// Full routing information for a sync operation.
public struct SyncRoutingInfo: Equatable, Sendable {
    public let database: SyncDatabase
    public let zoneID: CKRecordZone.ID

    public init(database: SyncDatabase, zoneID: CKRecordZone.ID) {
        self.database = database
        self.zoneID = zoneID
    }
}

/// Determines which database and zone to route sync operations to based on share state.
public final class ShareZoneRegistry: @unchecked Sendable {
    private let privateZoneID: CKRecordZone.ID

    public init(privateZoneID: CKRecordZone.ID) {
        self.privateZoneID = privateZoneID
    }

    /// Returns routing info for a Pinboard.
    public func routingInfo(for pinboard: Pinboard) -> SyncRoutingInfo {
        guard let meta = pinboard.shareMetadata else {
            return SyncRoutingInfo(database: .privateDB, zoneID: privateZoneID)
        }

        if meta.isOwner {
            let zoneID = CKRecordZone.ID(
                zoneName: meta.zoneName,
                ownerName: CKCurrentUserDefaultName
            )
            return SyncRoutingInfo(database: .privateDB, zoneID: zoneID)
        } else {
            let zoneID = CKRecordZone.ID(
                zoneName: meta.zoneName,
                ownerName: meta.zoneOwnerName
            )
            return SyncRoutingInfo(database: .sharedDB, zoneID: zoneID)
        }
    }

    /// Returns routing info for a ClipItem based on its pinboard memberships.
    ///
    /// If the item belongs to a shared pinboard, routes through the shared path.
    /// Items in only private pinboards route through the private path.
    public func routingInfo(for item: ClipItem) -> SyncRoutingInfo {
        guard let pinboards = item.pinboards else {
            return SyncRoutingInfo(database: .privateDB, zoneID: privateZoneID)
        }

        for pinboard in pinboards where pinboard.shareMetadata != nil {
            return routingInfo(for: pinboard)
        }

        return SyncRoutingInfo(database: .privateDB, zoneID: privateZoneID)
    }
}
