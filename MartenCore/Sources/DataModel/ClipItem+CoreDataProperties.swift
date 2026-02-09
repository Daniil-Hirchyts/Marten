import CoreData
import Foundation

public extension ClipItem {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ClipItem> {
        return NSFetchRequest<ClipItem>(entityName: "ClipItem")
    }

    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var displayOrder: Int64
    @NSManaged var sourceAppBundleID: String?
    @NSManaged var sourceAppName: String?
    @NSManaged var itemType: Int16
    @NSManaged var primaryText: String?
    @NSManaged var customTitle: String?
    @NSManaged var searchableText: String?
    @NSManaged var contentHash: String
    @NSManaged var isSensitive: Bool
    @NSManaged var isTransient: Bool
    @NSManaged var needsLinkPreview: Bool
    @NSManaged var thumbnailPath: String?
    @NSManaged var byteCount: Int64
    @NSManaged var isUserCreated: Bool
    @NSManaged var isPinned: Bool
    @NSManaged var representations: Set<ClipRepresentation>?
    @NSManaged var pinboards: Set<Pinboard>?
    @NSManaged var stackEntries: Set<StackEntry>?
    @NSManaged var linkPreview: LinkPreview?
}

extension ClipItem: Identifiable {}

public extension ClipItem {
    @objc(addRepresentationsObject:)
    @NSManaged func addToRepresentations(_ value: ClipRepresentation)

    @objc(removeRepresentationsObject:)
    @NSManaged func removeFromRepresentations(_ value: ClipRepresentation)

    @objc(addRepresentations:)
    @NSManaged func addToRepresentations(_ values: Set<ClipRepresentation>)

    @objc(removeRepresentations:)
    @NSManaged func removeFromRepresentations(_ values: Set<ClipRepresentation>)

    @objc(addPinboardsObject:)
    @NSManaged func addToPinboards(_ value: Pinboard)

    @objc(removePinboardsObject:)
    @NSManaged func removeFromPinboards(_ value: Pinboard)

    @objc(addPinboards:)
    @NSManaged func addToPinboards(_ values: Set<Pinboard>)

    @objc(removePinboards:)
    @NSManaged func removeFromPinboards(_ values: Set<Pinboard>)

    @objc(addStackEntriesObject:)
    @NSManaged func addToStackEntries(_ value: StackEntry)

    @objc(removeStackEntriesObject:)
    @NSManaged func removeFromStackEntries(_ value: StackEntry)

    @objc(addStackEntries:)
    @NSManaged func addToStackEntries(_ values: Set<StackEntry>)

    @objc(removeStackEntries:)
    @NSManaged func removeFromStackEntries(_ values: Set<StackEntry>)
}
