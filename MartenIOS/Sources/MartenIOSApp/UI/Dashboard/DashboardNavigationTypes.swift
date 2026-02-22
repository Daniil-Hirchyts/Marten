import CoreData
import Foundation
import MartenCore

enum DashboardActiveDestination: Identifiable {
    case richText(NSManagedObjectID)
    case image(NSManagedObjectID)
    case code(NSManagedObjectID)
    case url(NSManagedObjectID)

    var id: String {
        switch self {
        case .richText(let objectID):
            return "rich-\(objectID.uriRepresentation().absoluteString)"
        case .image(let objectID):
            return "image-\(objectID.uriRepresentation().absoluteString)"
        case .code(let objectID):
            return "code-\(objectID.uriRepresentation().absoluteString)"
        case .url(let objectID):
            return "url-\(objectID.uriRepresentation().absoluteString)"
        }
    }
}

struct DashboardPinboardEditorContext: Identifiable {
    let objectIDURI: String
    let name: String
    let colorHex: String
    let iconName: String?

    var id: String { objectIDURI }
}

struct DashboardPinboardShareContext: Identifiable {
    let pinboardID: NSManagedObjectID
    let initialAccessControl: ShareAccessControl
    let initialPermission: SharePermission
    let initialShareURL: URL?

    var id: String { pinboardID.uriRepresentation().absoluteString }
}

struct DashboardShareSheetContext: Identifiable {
    let id = UUID()
    let items: [Any]
}

