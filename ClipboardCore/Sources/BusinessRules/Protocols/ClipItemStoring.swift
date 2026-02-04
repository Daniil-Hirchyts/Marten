import CoreData
import Foundation

public protocol ClipItemStoring: Sendable {
    @discardableResult
    func createItem(payload: ClipItemPayload, sourceApp: SourceAppInfo?, isUserCreated: Bool) throws
        -> ClipItem

    func deleteItem(objectID: NSManagedObjectID) throws
    func updateItem(_ item: ClipItem, with payload: ClipItemPayload) throws
    func toggleFavorite(_ item: ClipItem) throws
    func moveItemsToPinboard(_ items: [ClipItem], pinboard: Pinboard) throws
}
