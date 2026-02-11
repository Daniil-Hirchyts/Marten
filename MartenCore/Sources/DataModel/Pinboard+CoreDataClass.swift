import CoreData
import Foundation

@objc(Pinboard)
public class Pinboard: NSManagedObject {
}

public extension Pinboard {
    var itemCount: Int {
        return items?.count ?? 0
    }

    var isShared: Bool {
        shareMetadata != nil
    }

    var shareRole: ShareRole {
        guard let meta = shareMetadata else { return .unknown }
        if meta.isOwner { return .owner }
        return ShareRole(rawValue: meta.defaultPermissionRaw) ?? .unknown
    }

    var canMakeChanges: Bool {
        guard isShared else { return true }
        let role = shareRole
        return role == .owner || role == .canMakeChanges
    }
}
