import CoreData
import Foundation

public extension Pinboard {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Pinboard> {
        return NSFetchRequest<Pinboard>(entityName: "Pinboard")
    }

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var colorHex: String
    @NSManaged var sortOrder: Int16
    @NSManaged var isSystemClipboard: Bool
    @NSManaged var createdAt: Date
    @NSManaged var iconName: String?
    @NSManaged var shareToken: String?
    @NSManaged var items: Set<ClipItem>?
}

extension Pinboard: Identifiable {}

public extension Pinboard {
    @objc(addItemsObject:)
    @NSManaged func addToItems(_ value: ClipItem)

    @objc(removeItemsObject:)
    @NSManaged func removeFromItems(_ value: ClipItem)

    @objc(addItems:)
    @NSManaged func addToItems(_ values: Set<ClipItem>)

    @objc(removeItems:)
    @NSManaged func removeFromItems(_ values: Set<ClipItem>)
}
