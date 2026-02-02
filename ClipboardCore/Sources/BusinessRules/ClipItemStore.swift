import CoreData
import Foundation

public final class ClipItemStore {
    private let repository: ClipItemRepository
    private let pinboardRepository: PinboardRepository
    private let assetManagementService: AssetManagementService
    private let retentionService: ClipItemRetentionService
    private let usageService: ClipItemUsageService
    private let searchService: SearchService

    public init(persistence: PersistenceController = .shared, assetStore: AssetStore = .shared) {
        let pinboardRepository = PinboardRepository(persistence: persistence)
        let searchService = SearchService(persistence: persistence)
        let assetManagementService = AssetManagementService(
            persistence: persistence,
            assetStore: assetStore
        )

        self.repository = ClipItemRepository(
            persistence: persistence,
            assetStore: assetStore,
            pinboardRepository: pinboardRepository,
            searchService: searchService,
            assetManagementService: assetManagementService
        )
        self.pinboardRepository = pinboardRepository
        self.assetManagementService = assetManagementService
        self.retentionService = ClipItemRetentionService(
            persistence: persistence,
            assetManagementService: assetManagementService
        )
        self.usageService = ClipItemUsageService(persistence: persistence)
        self.searchService = searchService
    }

    @discardableResult
    public func createTextItem(
        text: String,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        try repository.createTextItem(
            text: text,
            sourceApp: sourceApp,
            isUserCreated: isUserCreated
        )
    }

    @discardableResult
    public func createItem(
        payload: ClipItemPayload,
        sourceApp: SourceAppInfo? = nil,
        isUserCreated: Bool = false
    ) throws -> ClipItem {
        try repository.createItem(
            payload: payload,
            sourceApp: sourceApp,
            isUserCreated: isUserCreated
        )
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
        try retentionService.cleanupExpiredItems(policy: policy, now: now)
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
        try pinboardRepository.fetchPinboards()
    }

    @discardableResult
    public func createPinboard(name: String, colorHex: String, iconName: String? = nil) throws
        -> Pinboard
    {
        try pinboardRepository.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
    }

    public func renamePinboard(objectID: NSManagedObjectID, name: String, colorHex: String? = nil)
        throws
    {
        try pinboardRepository.renamePinboard(objectID: objectID, name: name, colorHex: colorHex)
    }

    public func deletePinboard(objectID: NSManagedObjectID) throws {
        try pinboardRepository.deletePinboard(objectID: objectID)
    }

    public func renameItem(objectID: NSManagedObjectID, title: String?) throws {
        try repository.renameItem(objectID: objectID, title: title)
    }

    public func addItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try pinboardRepository.addItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func removeItem(objectID: NSManagedObjectID, fromPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try pinboardRepository.removeItem(objectID: objectID, fromPinboard: pinboardID)
    }

    public func moveItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try pinboardRepository.moveItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func updateThumbnail(
        objectID: NSManagedObjectID,
        data: Data,
        fileExtension: String = "png"
    ) throws {
        try assetManagementService.updateThumbnail(
            objectID: objectID,
            data: data,
            fileExtension: fileExtension
        )
    }

    public func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws {
        try assetManagementService.updateLinkPreview(objectID: objectID, payload: payload)
    }

    public func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws {
        try assetManagementService.updateImageData(objectID: objectID, imageData: imageData)
    }

    public func updateFileName(objectID: NSManagedObjectID, newFileName: String) throws {
        try repository.updateFileName(objectID: objectID, newFileName: newFileName)
    }

    public func markLinkPreviewFetchFailed(
        objectID: NSManagedObjectID,
        url: URL,
        fetchedAt: Date = Date()
    ) throws {
        try assetManagementService.markLinkPreviewFetchFailed(
            objectID: objectID,
            url: url,
            fetchedAt: fetchedAt
        )
    }

    public func fetchPendingLinkPreviewTargets(limit: Int = 25) throws -> [(
        objectID: NSManagedObjectID,
        url: URL
    )] {
        try assetManagementService.fetchPendingLinkPreviewTargets(limit: limit)
    }

    public func markItemUsed(objectID: NSManagedObjectID, now: Date = Date()) throws {
        try usageService.markItemUsed(objectID: objectID, now: now)
    }

    public func markItemsUsed(objectIDs: [NSManagedObjectID], now: Date = Date()) throws {
        try usageService.markItemsUsed(objectIDs: objectIDs, now: now)
    }

    public func reorderItems(objectIDs: [NSManagedObjectID]) throws {
        try usageService.reorderItems(objectIDs: objectIDs)
    }

    public func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws {
        try pinboardRepository.reorderPinboards(orderedIDs: orderedIDs)
    }

    public func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws
        -> [ClipItem]
    {
        try searchService.searchItems(query: query, limit: limit, pinboardID: pinboardID)
    }

    public func saveChanges() throws {
        try repository.saveChanges()
    }
}

extension ClipItemStore: @unchecked Sendable {}
