import CoreData
import Foundation

public extension ShareMetadata {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ShareMetadata> {
        return NSFetchRequest<ShareMetadata>(entityName: "ShareMetadata")
    }

    @NSManaged var id: UUID
    @NSManaged var shareRecordName: String
    @NSManaged var rootRecordName: String
    @NSManaged var zoneName: String
    @NSManaged var zoneOwnerName: String
    @NSManaged var ownerUserRecordName: String?
    @NSManaged var accessControlRaw: Int16
    @NSManaged var defaultPermissionRaw: Int16
    @NSManaged var isOwner: Bool
    @NSManaged var shareURL: String?
    @NSManaged var lastParticipantRefreshAt: Date?
    @NSManaged var pinboard: Pinboard
}

extension ShareMetadata: Identifiable {}

public extension ShareMetadata {
    var accessControl: ShareAccessControl {
        get { ShareAccessControl(rawValue: accessControlRaw) ?? .onlyInvited }
        set { accessControlRaw = newValue.rawValue }
    }

    var defaultPermission: SharePermission {
        get { SharePermission(rawValue: defaultPermissionRaw) ?? .canMakeChanges }
        set { defaultPermissionRaw = newValue.rawValue }
    }
}
