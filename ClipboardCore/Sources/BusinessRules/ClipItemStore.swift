import CoreData
import Foundation

public final class ClipItemStore {
    private let repository: ClipItemRepository

    public init(persistence: PersistenceController = .shared, assetStore: AssetStore = .shared) {
        self.repository = ClipItemRepository(persistence: persistence, assetStore: assetStore)
    }

    @discardableResult
    public func createTextItem(
        text: String,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        try repository.createTextItem(
            text: text, sourceApp: sourceApp, isUserCreated: isUserCreated)
    }

    @discardableResult
    public func createItem(
        payload: ClipItemPayload,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        try repository.createItem(
            payload: payload, sourceApp: sourceApp, isUserCreated: isUserCreated)
    }

    public static func deleteAll() {
        ClipItemRepository.deleteAll()
    }

    public func deleteAllItems() throws {
        try repository.deleteAllItems()
    }

    public func fetchRecentItems(limit: Int = 100) throws -> [ClipItem] {
        try repository.fetchRecentItems(limit: limit)
    }

    @discardableResult
    public func cleanupExpiredItems(policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        try repository.cleanupExpiredItems(policy: policy, now: now)
    }

    @discardableResult
    public func updateTextItem(objectID: NSManagedObjectID, newText: String) throws -> ClipItem {
        try repository.updateTextItem(objectID: objectID, newText: newText)
    }

    @discardableResult
    public func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data)
        throws -> ClipItem
    {
        try repository.updateRichTextItem(objectID: objectID, newText: newText, rtfData: rtfData)
    }

    public func deleteItem(objectID: NSManagedObjectID) throws {
        try repository.deleteItem(objectID: objectID)
    }

    public func fetchPinboards() throws -> [Pinboard] {
        try repository.fetchPinboards()
    }

    @discardableResult
    public func createPinboard(name: String, colorHex: String, iconName: String? = nil) throws
        -> Pinboard
    {
        try repository.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
    }

    public func renamePinboard(objectID: NSManagedObjectID, name: String, colorHex: String? = nil)
        throws
    {
        try repository.renamePinboard(objectID: objectID, name: name, colorHex: colorHex)
    }

    public func deletePinboard(objectID: NSManagedObjectID) throws {
        try repository.deletePinboard(objectID: objectID)
    }

    public func renameItem(objectID: NSManagedObjectID, title: String?) throws {
        try repository.renameItem(objectID: objectID, title: title)
    }

    public func addItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try repository.addItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func removeItem(objectID: NSManagedObjectID, fromPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try repository.removeItem(objectID: objectID, fromPinboard: pinboardID)
    }

    public func moveItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try repository.moveItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func updateThumbnail(
        objectID: NSManagedObjectID,
        data: Data,
        fileExtension: String = "png"
    ) throws {
        try repository.updateThumbnail(objectID: objectID, data: data, fileExtension: fileExtension)
    }

    public func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws {
        try repository.updateLinkPreview(objectID: objectID, payload: payload)
    }

    public func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws {
        try repository.updateImageData(objectID: objectID, imageData: imageData)
    }

    public func updateFileName(objectID: NSManagedObjectID, newFileName: String) throws {
        try repository.updateFileName(objectID: objectID, newFileName: newFileName)
    }

    public func markLinkPreviewFetchFailed(
        objectID: NSManagedObjectID,
        url: URL,
        fetchedAt: Date = Date()
    ) throws {
        try repository.markLinkPreviewFetchFailed(
            objectID: objectID, url: url, fetchedAt: fetchedAt)
    }

    public func fetchPendingLinkPreviewTargets(limit: Int = 25) throws -> [(
        objectID: NSManagedObjectID,
        url: URL
    )] {
        try repository.fetchPendingLinkPreviewTargets(limit: limit)
    }

    public func markItemUsed(objectID: NSManagedObjectID, now: Date = Date()) throws {
        try repository.markItemUsed(objectID: objectID, now: now)
    }

    public func markItemsUsed(objectIDs: [NSManagedObjectID], now: Date = Date()) throws {
        try repository.markItemsUsed(objectIDs: objectIDs, now: now)
    }

    public func reorderItems(objectIDs: [NSManagedObjectID]) throws {
        try repository.reorderItems(objectIDs: objectIDs)
    }

    public func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws {
        try repository.reorderPinboards(orderedIDs: orderedIDs)
    }

    public func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws
        -> [ClipItem]
    {
        try repository.searchItems(query: query, limit: limit, pinboardID: pinboardID)
    }

    public func saveChanges() throws {
        try repository.saveChanges()
    }
}

extension ClipItemStore: @unchecked Sendable {}
