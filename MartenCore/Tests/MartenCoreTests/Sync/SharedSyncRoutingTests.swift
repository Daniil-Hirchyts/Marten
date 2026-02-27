import CloudKit
import Combine
import CoreData
import XCTest
@testable import MartenCore

final class SharedSyncRoutingTests: XCTestCase {
    private var persistence: PersistenceController!
    private var registry: ShareZoneRegistry!
    private var cancellables: Set<AnyCancellable> = []
    private let privateZoneID = CKRecordZone.ID(
        zoneName: "MartenClipboardZone",
        ownerName: CKCurrentUserDefaultName
    )

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        registry = ShareZoneRegistry(privateZoneID: privateZoneID)
    }

    override func tearDown() {
        persistence = nil
        registry = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Pinboard Routing

    func testUnsharedPinboardRoutesToPrivateDB() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        try context.save()

        let routing = registry.routingInfo(for: pinboard)
        XCTAssertEqual(routing.database, .privateDB)
        XCTAssertEqual(routing.zoneID, privateZoneID)
    }

    func testOwnerSharedPinboardRoutesToPrivateDBSharedZone() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(
            in: context,
            pinboard: pinboard,
            isOwner: true,
            zoneName: "SharedPinboard-ABC",
            zoneOwnerName: CKCurrentUserDefaultName
        )
        pinboard.shareMetadata = meta
        try context.save()

        let routing = registry.routingInfo(for: pinboard)
        XCTAssertEqual(routing.database, .privateDB)
        XCTAssertEqual(routing.zoneID.zoneName, "SharedPinboard-ABC")
    }

    func testParticipantSharedPinboardRoutesToSharedDB() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(
            in: context,
            pinboard: pinboard,
            isOwner: false,
            zoneName: "SharedPinboard-XYZ",
            zoneOwnerName: "ownerRecord123"
        )
        pinboard.shareMetadata = meta
        try context.save()

        let routing = registry.routingInfo(for: pinboard)
        XCTAssertEqual(routing.database, .sharedDB)
        XCTAssertEqual(routing.zoneID.zoneName, "SharedPinboard-XYZ")
        XCTAssertEqual(routing.zoneID.ownerName, "ownerRecord123")
    }

    func testTokenReconciliationRestoresSharedRouting() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let token = ShareTokenEnvelope(
            shareRecordName: "share-restored",
            rootRecordName: "root-restored",
            zoneName: "SharedPinboard-RESTORED",
            zoneOwnerName: "participantOwner",
            isOwner: false,
            accessControlRaw: ShareAccessControl.onlyInvited.rawValue,
            defaultPermissionRaw: SharePermission.canMakeChanges.rawValue,
            shareURL: nil
        )
        pinboard.shareToken = token.encodedString()
        try context.save()

        _ = try ShareMetadataReconciler().reconcile(persistenceController: persistence)

        context.refreshAllObjects()
        context.processPendingChanges()

        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", pinboard.id as CVarArg)
        request.fetchLimit = 1
        let refreshed = try XCTUnwrap(context.fetch(request).first)
        let routing = registry.routingInfo(for: refreshed)

        XCTAssertEqual(routing.database, .sharedDB)
        XCTAssertEqual(routing.zoneID.zoneName, "SharedPinboard-RESTORED")
        XCTAssertEqual(routing.zoneID.ownerName, "participantOwner")
        XCTAssertNotNil(refreshed.shareMetadata)
    }

    // MARK: - ClipItem Routing

    func testItemInPrivatePinboardRoutesToPrivateDB() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let item = try makeClipItem(in: context)
        item.addToPinboards(pinboard)
        try context.save()

        let routing = registry.routingInfo(for: item)
        XCTAssertEqual(routing.database, .privateDB)
        XCTAssertEqual(routing.zoneID, privateZoneID)
    }

    func testItemInSharedPinboardRoutesViaSharedPath() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(
            in: context,
            pinboard: pinboard,
            isOwner: true,
            zoneName: "SharedPinboard-DEF",
            zoneOwnerName: CKCurrentUserDefaultName
        )
        pinboard.shareMetadata = meta
        let item = try makeClipItem(in: context)
        item.addToPinboards(pinboard)
        try context.save()

        let routing = registry.routingInfo(for: item)
        XCTAssertEqual(routing.database, .privateDB)
        XCTAssertEqual(routing.zoneID.zoneName, "SharedPinboard-DEF")
    }

    func testItemWithNoPinboardsRoutesToPrivateDB() throws {
        let context = persistence.viewContext
        let item = try makeClipItem(in: context)
        try context.save()

        let routing = registry.routingInfo(for: item)
        XCTAssertEqual(routing.database, .privateDB)
        XCTAssertEqual(routing.zoneID, privateZoneID)
    }

    func testSharedOutboundMissingAssetPublishesErrorAndSkipsRepresentationUpload() async throws {
        let privateDatabase = MockOutboundCloudDatabase()
        let sharedDatabase = MockOutboundCloudDatabase()
        let mapper = CloudRecordMapper(zoneID: privateZoneID)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let assetStore = AssetStore(baseURL: tempDirectory)
        let assetSyncManager = AssetSyncManager(assetStore: assetStore)
        let engine = SharedOutboundSyncEngine(
            persistenceController: persistence,
            privateDatabase: privateDatabase,
            sharedDatabase: sharedDatabase,
            shareZoneRegistry: registry,
            recordMapper: mapper,
            debounceInterval: 0.01,
            assetSyncManager: assetSyncManager,
            attachmentRetryBackoff: 0.01,
            attachmentMaxRetries: 2
        )

        var preparationErrors: [SyncRecordPreparationError] = []
        let preparationErrorsExpectation = expectation(description: "shared preparation errors")
        preparationErrorsExpectation.expectedFulfillmentCount = 2
        preparationErrorsExpectation.assertForOverFulfill = true
        engine.preparationErrorPublisher
            .sink { error in
                preparationErrors.append(error)
                preparationErrorsExpectation.fulfill()
            }
            .store(in: &cancellables)

        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let metadata = try makeShareMetadata(
            in: context,
            pinboard: pinboard,
            isOwner: false,
            zoneName: "SharedPinboard-MISSING-ASSET",
            zoneOwnerName: "participant-owner"
        )
        pinboard.shareMetadata = metadata

        let item = try makeClipItem(in: context)
        item.primaryText = "shared-missing-asset"
        item.contentHash = "hash-\(UUID().uuidString)"
        item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
        item.addToPinboards(pinboard)

        let representation = NSEntityDescription.insertNewObject(
            forEntityName: "ClipRepresentation",
            into: context
        ) as! ClipRepresentation
        representation.id = UUID()
        representation.uti = "public.png"
        representation.kindValue = .png
        representation.displayOrder = 0
        representation.fileExtension = "png"
        representation.assetRef = UUID()
        representation.textData = nil
        representation.byteCount = 2_048
        representation.clipItem = item

        try context.save()

        await fulfillment(of: [preparationErrorsExpectation], timeout: 1.5)
        await engine.flushAndAwait()

        let routing = registry.routingInfo(for: item)
        XCTAssertEqual(routing.database, .sharedDB)

        let representationRecordID = CKRecord.ID.clipRepresentationID(
            representation.id,
            zoneID: routing.zoneID
        )
        let sharedSavedRecords = await sharedDatabase.calls.flatMap(\.saved)
        let privateSavedRecords = await privateDatabase.calls.flatMap(\.saved)
        XCTAssertFalse(sharedSavedRecords.contains(where: { $0.recordID == representationRecordID }))
        XCTAssertFalse(privateSavedRecords.contains(where: { $0.recordID == representationRecordID }))

        XCTAssertEqual(preparationErrors.count, 2)
        for preparationError in preparationErrors {
            guard
                case .assetAttachmentFailed(
                    engine: let engineName,
                    representationID: let failedRepresentationID,
                    reason: let reason
                ) = preparationError
            else {
                XCTFail("Unexpected shared preparation error case: \(preparationError)")
                continue
            }
            XCTAssertEqual(engineName, "SharedOutboundSyncEngine")
            XCTAssertEqual(failedRepresentationID, representation.id)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    // MARK: - Helpers

    private func makePinboard(in context: NSManagedObjectContext) throws -> Pinboard {
        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard", into: context
        ) as? Pinboard else {
            throw NSError(domain: "test", code: 1)
        }
        pinboard.id = UUID()
        pinboard.name = "Test Pinboard"
        pinboard.colorHex = "#FF0000"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        return pinboard
    }

    private func makeClipItem(in context: NSManagedObjectContext) throws -> ClipItem {
        guard let item = NSEntityDescription.insertNewObject(
            forEntityName: "ClipItem", into: context
        ) as? ClipItem else {
            throw NSError(domain: "test", code: 1)
        }
        item.id = UUID()
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.itemType = ItemType.text.rawValue
        item.byteCount = 0
        item.isTransient = false
        return item
    }

    private func makeShareMetadata(
        in context: NSManagedObjectContext,
        pinboard: Pinboard,
        isOwner: Bool,
        zoneName: String,
        zoneOwnerName: String
    ) throws -> ShareMetadata {
        guard let meta = NSEntityDescription.insertNewObject(
            forEntityName: "ShareMetadata", into: context
        ) as? ShareMetadata else {
            throw NSError(domain: "test", code: 1)
        }
        meta.id = UUID()
        meta.shareRecordName = "share-\(UUID().uuidString)"
        meta.rootRecordName = "root-\(UUID().uuidString)"
        meta.zoneName = zoneName
        meta.zoneOwnerName = zoneOwnerName
        meta.isOwner = isOwner
        meta.accessControlRaw = 0
        meta.defaultPermissionRaw = 1
        meta.pinboard = pinboard
        return meta
    }
}
