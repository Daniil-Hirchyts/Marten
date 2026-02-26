import CoreData
import Foundation

public protocol ClipItemRepositoryProtocol: Sendable {
    @discardableResult
    func createTextItem(text: String, sourceApp: SourceAppInfo?, isUserCreated: Bool) throws -> ClipItem

    @discardableResult
    func createItem(payload: ClipItemPayload, sourceApp: SourceAppInfo?, isUserCreated: Bool) throws -> ClipItem

    func deleteAllItems() throws
    func deleteItemsFromThisDevice() throws
    func fetchRecentItems(limit: Int) throws -> [ClipItem]
    func fetchItems(
        primaryText: String,
        itemType: ItemType,
        limit: Int
    ) throws -> [ClipItem]

    @discardableResult
    func updateTextItem(objectID: NSManagedObjectID, newText: String) throws -> ClipItem

    @discardableResult
    func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data) throws -> ClipItem

    @discardableResult
    func updateItem(objectID: NSManagedObjectID, payload: ClipItemPayload) throws -> ClipItem

    @discardableResult
    func updateItemType(objectID: NSManagedObjectID, newType: ItemType) throws -> ClipItem

    func deleteItem(objectID: NSManagedObjectID) throws
    func togglePin(objectID: NSManagedObjectID) throws
    func toggleFavorite(objectID: NSManagedObjectID) throws
    func renameItem(objectID: NSManagedObjectID, title: String?) throws
    func updateFileName(objectID: NSManagedObjectID, newFileName: String) throws
    func saveChanges() throws
}
