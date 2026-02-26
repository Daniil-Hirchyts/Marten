import CoreData
import Foundation

public final class ClipItemStore {
    private let repository: any ClipItemRepositoryProtocol
    private let pinboardRepository: any PinboardRepositoryProtocol
    private let assetManagementService: any AssetManagementServicing
    private let retentionService: any ClipItemRetentionServicing
    private let usageService: any ClipItemUsageServicing
    private let searchService: any SearchServicing
    public let sharingRepository: (any PinboardSharingRepositoryProtocol)?

    public init(
        repository: any ClipItemRepositoryProtocol,
        retentionService: any ClipItemRetentionServicing,
        usageService: any ClipItemUsageServicing,
        assetManagementService: any AssetManagementServicing,
        pinboardRepository: any PinboardRepositoryProtocol,
        searchService: any SearchServicing,
        sharingRepository: (any PinboardSharingRepositoryProtocol)? = nil
    ) {
        self.repository = repository
        self.retentionService = retentionService
        self.usageService = usageService
        self.assetManagementService = assetManagementService
        self.pinboardRepository = pinboardRepository
        self.searchService = searchService
        self.sharingRepository = sharingRepository
    }

    public convenience init(persistence: PersistenceController = .shared, assetStore: AssetStore = .shared) {
        let pinboardRepository = PinboardRepository(persistence: persistence)
        let searchService = SearchService(persistence: persistence)
        let assetManagementService = AssetManagementService(
            persistence: persistence,
            assetStore: assetStore
        )

        let repository = ClipItemRepository(
            persistence: persistence,
            assetStore: assetStore,
            pinboardRepository: pinboardRepository,
            searchService: searchService,
            assetManagementService: assetManagementService
        )
        let retentionService = ClipItemRetentionService(
            persistence: persistence,
            assetManagementService: assetManagementService
        )
        let usageService = ClipItemUsageService(persistence: persistence)

        self.init(
            repository: repository,
            retentionService: retentionService,
            usageService: usageService,
            assetManagementService: assetManagementService,
            pinboardRepository: pinboardRepository,
            searchService: searchService
        )
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
        try? ClipItemStore().deleteAllItems()
    }

    public func deleteAllItems() throws {
        try repository.deleteAllItems()
        try pinboardRepository.deleteUserPinboards()
    }

    public func deleteItemsFromThisDevice() throws {
        try repository.deleteItemsFromThisDevice()
    }

    public func fetchRecentItems(limit: Int = 100) throws -> [ClipItem] {
        try repository.fetchRecentItems(limit: limit)
    }

    public func fetchItems(
        primaryText: String,
        itemType: ItemType,
        limit: Int = 50
    ) throws -> [ClipItem] {
        try repository.fetchItems(
            primaryText: primaryText,
            itemType: itemType,
            limit: limit
        )
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

    @discardableResult
    public func updateItemType(objectID: NSManagedObjectID, newType: ItemType) throws -> ClipItem {
        try repository.updateItemType(objectID: objectID, newType: newType)
    }

    public func deleteItem(objectID: NSManagedObjectID) throws {
        try repository.deleteItem(objectID: objectID)
    }

    public func updateItem(_ item: ClipItem, with payload: ClipItemPayload) throws {
        _ = try repository.updateItem(objectID: item.objectID, payload: payload)
    }

    public func toggleFavorite(_ item: ClipItem) throws {
        try repository.toggleFavorite(objectID: item.objectID)
    }

    public func togglePin(_ item: ClipItem) throws {
        try repository.togglePin(objectID: item.objectID)
    }

    public func togglePin(objectID: NSManagedObjectID) throws {
        try repository.togglePin(objectID: objectID)
    }

    public func moveItemsToPinboard(_ items: [ClipItem], pinboard: Pinboard) throws {
        try pinboardRepository.moveItems(
            objectIDs: items.map { $0.objectID },
            toPinboard: pinboard.objectID
        )
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

    public func updatePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) throws {
        try pinboardRepository.updatePinboard(
            objectID: objectID,
            name: name,
            colorHex: colorHex,
            iconName: iconName
        )
    }

    public func deletePinboard(objectID: NSManagedObjectID) throws {
        try pinboardRepository.deletePinboard(objectID: objectID)
    }

    public func deleteUserPinboards() throws {
        try pinboardRepository.deleteUserPinboards()
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

    public func moveItems(objectIDs: [NSManagedObjectID], toPinboard pinboardID: NSManagedObjectID)
        throws
    {
        try pinboardRepository.moveItems(objectIDs: objectIDs, toPinboard: pinboardID)
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

    public func searchItems(request: ClipItemSearchRequest) throws -> [ClipItem] {
        try searchService.searchItems(request: request)
    }

    public func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws
        -> [ClipItem]
    {
        try searchService.searchItems(
            request: ClipItemSearchRequest(
                query: query,
                pinboardID: pinboardID,
                limit: limit
            )
        )
    }

    public func saveChanges() throws {
        try repository.saveChanges()
    }
}

// SAFETY: ClipItemStore is a thin, immutable facade that forwards into services which serialize
// Core Data access on their context queues (via `performAndWaitThrowing`).
extension ClipItemStore: @unchecked Sendable {}

extension ClipItemStore: ClipItemStoring {}
