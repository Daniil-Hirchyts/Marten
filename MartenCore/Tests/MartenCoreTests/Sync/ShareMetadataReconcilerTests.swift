import CloudKit
import CoreData
import XCTest
@testable import MartenCore

final class ShareMetadataReconcilerTests: XCTestCase {
    private var persistence: PersistenceController!
    private var reconciler: ShareMetadataReconciler!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        reconciler = ShareMetadataReconciler()
    }

    override func tearDown() {
        reconciler = nil
        persistence = nil
        super.tearDown()
    }

    func testReconcileCreatesShareMetadataFromValidToken() throws {
        let context = persistence.viewContext
        let pinboard = makePinboard(in: context)
        let token = ShareTokenEnvelope(
            shareRecordName: "share-record-1",
            rootRecordName: "root-record-1",
            zoneName: "SharedPinboard-ABC",
            zoneOwnerName: "owner-abc",
            isOwner: false,
            accessControlRaw: ShareAccessControl.onlyInvited.rawValue,
            defaultPermissionRaw: SharePermission.canMakeChanges.rawValue,
            shareURL: "https://example.com/share/1"
        )
        pinboard.shareToken = token.encodedString()
        try context.save()

        let result = try reconciler.reconcile(persistenceController: persistence)

        XCTAssertEqual(result.createdCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(
            result.discoveredSharedZoneIDs,
            [CKRecordZone.ID(zoneName: "SharedPinboard-ABC", ownerName: "owner-abc")]
        )

        let refreshed = try fetchPinboard(id: pinboard.id, in: context)
        XCTAssertEqual(refreshed.shareMetadata?.shareRecordName, "share-record-1")
        XCTAssertEqual(refreshed.shareMetadata?.rootRecordName, "root-record-1")
        XCTAssertEqual(refreshed.shareMetadata?.zoneName, "SharedPinboard-ABC")
        XCTAssertEqual(refreshed.shareMetadata?.zoneOwnerName, "owner-abc")
        XCTAssertEqual(refreshed.shareMetadata?.isOwner, false)
        XCTAssertEqual(refreshed.shareMetadata?.defaultPermissionRaw, SharePermission.canMakeChanges.rawValue)
    }

    func testReconcileRemovesShareMetadataWhenTokenMissing() throws {
        let context = persistence.viewContext
        let pinboard = makePinboard(in: context)
        _ = makeShareMetadata(
            in: context,
            pinboard: pinboard,
            shareRecordName: "legacy-share",
            rootRecordName: "legacy-root",
            zoneName: "SharedPinboard-OLD",
            zoneOwnerName: "owner-old",
            isOwner: false
        )
        pinboard.shareToken = nil
        try context.save()

        let result = try reconciler.reconcile(persistenceController: persistence)

        XCTAssertEqual(result.createdCount, 0)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertTrue(result.discoveredSharedZoneIDs.isEmpty)

        let refreshed = try fetchPinboard(id: pinboard.id, in: context)
        XCTAssertNil(refreshed.shareMetadata)
    }

    func testReconcileUpdatesStaleShareMetadataFromToken() throws {
        let context = persistence.viewContext
        let pinboard = makePinboard(in: context)
        let existing = makeShareMetadata(
            in: context,
            pinboard: pinboard,
            shareRecordName: "old-share",
            rootRecordName: "old-root",
            zoneName: "SharedPinboard-OLD",
            zoneOwnerName: "owner-old",
            isOwner: false
        )
        existing.defaultPermissionRaw = SharePermission.viewOnly.rawValue

        let token = ShareTokenEnvelope(
            shareRecordName: "new-share",
            rootRecordName: "new-root",
            zoneName: "SharedPinboard-NEW",
            zoneOwnerName: "owner-new",
            isOwner: false,
            accessControlRaw: ShareAccessControl.anyoneWithLink.rawValue,
            defaultPermissionRaw: SharePermission.canMakeChanges.rawValue,
            shareURL: "https://example.com/share/new"
        )
        pinboard.shareToken = token.encodedString()
        try context.save()

        let result = try reconciler.reconcile(persistenceController: persistence)

        XCTAssertEqual(result.createdCount, 0)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(
            result.discoveredSharedZoneIDs,
            [CKRecordZone.ID(zoneName: "SharedPinboard-NEW", ownerName: "owner-new")]
        )

        let refreshed = try fetchPinboard(id: pinboard.id, in: context)
        XCTAssertEqual(refreshed.shareMetadata?.shareRecordName, "new-share")
        XCTAssertEqual(refreshed.shareMetadata?.rootRecordName, "new-root")
        XCTAssertEqual(refreshed.shareMetadata?.zoneName, "SharedPinboard-NEW")
        XCTAssertEqual(refreshed.shareMetadata?.zoneOwnerName, "owner-new")
        XCTAssertEqual(refreshed.shareMetadata?.accessControlRaw, ShareAccessControl.anyoneWithLink.rawValue)
        XCTAssertEqual(refreshed.shareMetadata?.defaultPermissionRaw, SharePermission.canMakeChanges.rawValue)
        XCTAssertEqual(refreshed.shareMetadata?.shareURL, "https://example.com/share/new")
    }

    private func makePinboard(in context: NSManagedObjectContext) -> Pinboard {
        let pinboard = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
        pinboard.id = UUID()
        pinboard.name = "Test Pinboard"
        pinboard.colorHex = "#123456"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        return pinboard
    }

    private func makeShareMetadata(
        in context: NSManagedObjectContext,
        pinboard: Pinboard,
        shareRecordName: String,
        rootRecordName: String,
        zoneName: String,
        zoneOwnerName: String,
        isOwner: Bool
    ) -> ShareMetadata {
        let metadata = NSEntityDescription.insertNewObject(forEntityName: "ShareMetadata", into: context) as! ShareMetadata
        metadata.id = UUID()
        metadata.shareRecordName = shareRecordName
        metadata.rootRecordName = rootRecordName
        metadata.zoneName = zoneName
        metadata.zoneOwnerName = zoneOwnerName
        metadata.isOwner = isOwner
        metadata.accessControlRaw = ShareAccessControl.onlyInvited.rawValue
        metadata.defaultPermissionRaw = SharePermission.canMakeChanges.rawValue
        metadata.pinboard = pinboard
        return metadata
    }

    private func fetchPinboard(id: UUID, in context: NSManagedObjectContext) throws -> Pinboard {
        context.performAndWait {
            context.refreshAllObjects()
            context.processPendingChanges()
        }
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        guard let pinboard = try context.fetch(request).first else {
            throw NSError(domain: "ShareMetadataReconcilerTests", code: 1)
        }
        return pinboard
    }
}
