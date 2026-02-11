import CloudKit
import CoreData
import XCTest
@testable import MartenCore

final class SharedSyncRoutingTests: XCTestCase {
    private var persistence: PersistenceController!
    private var registry: ShareZoneRegistry!
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
