import CoreData
import Foundation

public extension ClipRepresentation {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ClipRepresentation> {
        return NSFetchRequest<ClipRepresentation>(entityName: "ClipRepresentation")
    }

    @NSManaged var id: UUID
    @NSManaged var uti: String
    @NSManaged var kind: Int16
    @NSManaged var displayOrder: Int16
    @NSManaged var textData: Data?
    @NSManaged var binaryData: Data?
    @NSManaged var assetRef: UUID?
    @NSManaged var fileExtension: String?
    @NSManaged var byteCount: Int64
    @NSManaged var clipItem: ClipItem?
}

extension ClipRepresentation: Identifiable {}
