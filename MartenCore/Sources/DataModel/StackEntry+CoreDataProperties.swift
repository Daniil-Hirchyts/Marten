import CoreData
import Foundation

public extension StackEntry {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StackEntry> {
        return NSFetchRequest<StackEntry>(entityName: "StackEntry")
    }

    @NSManaged var id: UUID
    @NSManaged var position: Int16
    @NSManaged var addedAt: Date
    @NSManaged var session: StackSession?
    @NSManaged var clipItem: ClipItem?
}

extension StackEntry: Identifiable {}
