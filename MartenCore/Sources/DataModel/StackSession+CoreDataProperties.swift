import CoreData
import Foundation

public extension StackSession {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StackSession> {
        return NSFetchRequest<StackSession>(entityName: "StackSession")
    }

    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var isActive: Bool
    @NSManaged var separator: String
    @NSManaged var mode: Int16
    @NSManaged var entries: Set<StackEntry>?
}

extension StackSession: Identifiable {}

public extension StackSession {
    @objc(addEntriesObject:)
    @NSManaged func addToEntries(_ value: StackEntry)

    @objc(removeEntriesObject:)
    @NSManaged func removeFromEntries(_ value: StackEntry)

    @objc(addEntries:)
    @NSManaged func addToEntries(_ values: Set<StackEntry>)

    @objc(removeEntries:)
    @NSManaged func removeFromEntries(_ values: Set<StackEntry>)
}
