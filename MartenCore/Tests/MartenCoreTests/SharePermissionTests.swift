import CloudKit
import CoreData
import XCTest
@testable import MartenCore

final class SharePermissionTests: XCTestCase {
    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        persistence = nil
        super.tearDown()
    }

    // MARK: - Pinboard isShared / shareRole / canMakeChanges

    func testUnsharedPinboardIsNotShared() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        try context.save()

        XCTAssertFalse(pinboard.isShared)
    }

    func testSharedPinboardIsShared() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertTrue(pinboard.isShared)
    }

    func testOwnerRoleIsOwner() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        meta.defaultPermissionRaw = SharePermission.owner.rawValue
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertEqual(pinboard.shareRole, .owner)
        XCTAssertTrue(pinboard.canMakeChanges)
    }

    func testParticipantCanMakeChanges() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: false)
        meta.defaultPermissionRaw = SharePermission.canMakeChanges.rawValue
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertEqual(pinboard.shareRole, .canMakeChanges)
        XCTAssertTrue(pinboard.canMakeChanges)
    }

    func testParticipantViewOnly() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: false)
        meta.defaultPermissionRaw = SharePermission.viewOnly.rawValue
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertEqual(pinboard.shareRole, .viewOnly)
        XCTAssertFalse(pinboard.canMakeChanges)
    }

    // MARK: - Lock / Share Mutual Exclusivity

    func testMixedMembershipPreventsAddingToSharedAndPrivatePinboards() throws {
        let context = persistence.newBackgroundContext()
        let repo = PinboardRepository(persistence: persistence)

        var sharedPinboardID: NSManagedObjectID!
        var privatePinboardID: NSManagedObjectID!
        var itemID: NSManagedObjectID!

        try context.performAndWait {
            let sharedPinboard = try makePinboard(in: context)
            let meta = try makeShareMetadata(in: context, pinboard: sharedPinboard, isOwner: true)
            sharedPinboard.shareMetadata = meta
            let privatePinboard = try makePinboard(in: context)
            let item = try makeClipItem(in: context)
            // First, add the item to the shared pinboard
            item.addToPinboards(sharedPinboard)
            try context.save()
            sharedPinboardID = sharedPinboard.objectID
            privatePinboardID = privatePinboard.objectID
            itemID = item.objectID
        }

        // Now try to add the same item to a private pinboard — should fail
        XCTAssertThrowsError(try repo.addItem(objectID: itemID, toPinboard: privatePinboardID)) { error in
            XCTAssertTrue(error is PinboardSharingError)
        }
    }

    // MARK: - ShareEnums Roundtrip

    func testShareAccessControlRoundtrip() {
        XCTAssertEqual(ShareAccessControl(rawValue: 0), .onlyInvited)
        XCTAssertEqual(ShareAccessControl(rawValue: 1), .anyoneWithLink)
        XCTAssertNil(ShareAccessControl(rawValue: 99))
    }

    func testSharePermissionRoundtrip() {
        XCTAssertEqual(SharePermission(rawValue: 0), .owner)
        XCTAssertEqual(SharePermission(rawValue: 1), .canMakeChanges)
        XCTAssertEqual(SharePermission(rawValue: 2), .viewOnly)
        XCTAssertNil(SharePermission(rawValue: 99))
    }

    func testShareRoleRoundtrip() {
        XCTAssertEqual(ShareRole(rawValue: 0), .owner)
        XCTAssertEqual(ShareRole(rawValue: 1), .canMakeChanges)
        XCTAssertEqual(ShareRole(rawValue: 2), .viewOnly)
        XCTAssertEqual(ShareRole(rawValue: 3), .unknown)
    }

    // MARK: - Helpers

    private func makePinboard(in context: NSManagedObjectContext) throws -> Pinboard {
        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard", into: context
        ) as? Pinboard else {
            throw NSError(domain: "test", code: 1)
        }
        pinboard.id = UUID()
        pinboard.name = "Test"
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
        isOwner: Bool
    ) throws -> ShareMetadata {
        guard let meta = NSEntityDescription.insertNewObject(
            forEntityName: "ShareMetadata", into: context
        ) as? ShareMetadata else {
            throw NSError(domain: "test", code: 1)
        }
        meta.id = UUID()
        meta.shareRecordName = "share-\(UUID().uuidString)"
        meta.rootRecordName = "root-\(UUID().uuidString)"
        meta.zoneName = "SharedPinboard-\(UUID().uuidString)"
        meta.zoneOwnerName = isOwner ? CKCurrentUserDefaultName : "someOwner"
        meta.isOwner = isOwner
        meta.accessControlRaw = 0
        meta.defaultPermissionRaw = 1
        meta.pinboard = pinboard
        return meta
    }
}
