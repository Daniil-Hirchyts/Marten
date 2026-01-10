import CoreData
import Foundation

public extension LinkPreview {
    @nonobjc class func fetchRequest() -> NSFetchRequest<LinkPreview> {
        return NSFetchRequest<LinkPreview>(entityName: "LinkPreview")
    }

    @NSManaged var id: UUID
    @NSManaged var url: String
    @NSManaged var title: String?
    @NSManaged var summary: String?
    @NSManaged var imageURL: String?
    @NSManaged var imagePath: String?
    @NSManaged var siteName: String?
    @NSManaged var fetchedAt: Date
    @NSManaged var fetchFailed: Bool
    @NSManaged var clipItem: ClipItem?
}

extension LinkPreview: Identifiable {}
