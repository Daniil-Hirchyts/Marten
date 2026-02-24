import CoreData
import Foundation
import MartenCore

enum DashboardPreviewDestination: Identifiable {
    case text(NSManagedObjectID)
    case image(NSManagedObjectID)
    case code(NSManagedObjectID)
    case url(NSManagedObjectID)
    case color(NSManagedObjectID)

    var id: String {
        switch self {
        case .text(let objectID):
            return "preview-text-\(objectID.uriRepresentation().absoluteString)"
        case .image(let objectID):
            return "preview-image-\(objectID.uriRepresentation().absoluteString)"
        case .code(let objectID):
            return "preview-code-\(objectID.uriRepresentation().absoluteString)"
        case .url(let objectID):
            return "preview-url-\(objectID.uriRepresentation().absoluteString)"
        case .color(let objectID):
            return "preview-color-\(objectID.uriRepresentation().absoluteString)"
        }
    }
}

enum DashboardEditDestination: Identifiable {
    case richText(NSManagedObjectID)
    case image(NSManagedObjectID)
    case code(NSManagedObjectID)
    case url(NSManagedObjectID)
    case color(NSManagedObjectID)

    var id: String {
        switch self {
        case .richText(let objectID):
            return "edit-rich-\(objectID.uriRepresentation().absoluteString)"
        case .image(let objectID):
            return "edit-image-\(objectID.uriRepresentation().absoluteString)"
        case .code(let objectID):
            return "edit-code-\(objectID.uriRepresentation().absoluteString)"
        case .url(let objectID):
            return "edit-url-\(objectID.uriRepresentation().absoluteString)"
        case .color(let objectID):
            return "edit-color-\(objectID.uriRepresentation().absoluteString)"
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
    let pinboardUUID: UUID
    let initialAccessControl: ShareAccessControl
    let initialPermission: SharePermission
    let initialShareURL: URL?

    var id: String { pinboardID.uriRepresentation().absoluteString }
}

struct DashboardShareSheetContext: Identifiable {
    let id = UUID()
    let items: [Any]
}
