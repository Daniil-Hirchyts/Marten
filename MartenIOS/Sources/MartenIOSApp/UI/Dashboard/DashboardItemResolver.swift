import CoreData
import Foundation
import MartenCore

protocol DashboardClipItemResolving {
    func resolveItems(from objectIDs: [NSManagedObjectID]) -> [ClipItem]
    func item(with objectID: NSManagedObjectID) -> ClipItem?
}

struct CoreDataDashboardClipItemResolver: DashboardClipItemResolving {
    let viewContext: NSManagedObjectContext

    func resolveItems(from objectIDs: [NSManagedObjectID]) -> [ClipItem] {
        objectIDs.compactMap { try? viewContext.existingObject(with: $0) as? ClipItem }
    }

    func item(with objectID: NSManagedObjectID) -> ClipItem? {
        try? viewContext.existingObject(with: objectID) as? ClipItem
    }
}

