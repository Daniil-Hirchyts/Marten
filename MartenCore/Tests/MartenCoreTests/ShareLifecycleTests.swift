import CloudKit
import CoreData
import XCTest
@testable import MartenCore

final class ShareLifecycleTests: XCTestCase {
    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        persistence = nil
        super.tearDown()
    }

    // MARK: - ShareMetadata Lifecycle

    func testShareMetadataCreation() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertTrue(pinboard.isShared)
        XCTAssertEqual(pinboard.shareRole, .owner)
        XCTAssertTrue(pinboard.canMakeChanges)
        XCTAssertNotNil(pinboard.shareMetadata)
        XCTAssertEqual(pinboard.shareMetadata?.pinboard.objectID, pinboard.objectID)
    }

    func testShareMetadataDeletionUnsharesPinboard() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        pinboard.shareMetadata = meta
        try context.save()

        XCTAssertTrue(pinboard.isShared)

        // Delete the share metadata
        context.delete(meta)
        try context.save()

        // Refresh to pick up the cascaded nullify
        context.refresh(pinboard, mergeChanges: true)
        XCTAssertFalse(pinboard.isShared)
        XCTAssertNil(pinboard.shareMetadata)
    }

    func testShareMetadataAccessControlComputed() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        try context.save()

        meta.accessControl = .anyoneWithLink
        XCTAssertEqual(meta.accessControlRaw, ShareAccessControl.anyoneWithLink.rawValue)
        XCTAssertEqual(meta.accessControl, .anyoneWithLink)

        meta.accessControl = .onlyInvited
        XCTAssertEqual(meta.accessControlRaw, ShareAccessControl.onlyInvited.rawValue)
    }

    func testShareMetadataDefaultPermissionComputed() throws {
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        let meta = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: true)
        try context.save()

        meta.defaultPermission = .viewOnly
        XCTAssertEqual(meta.defaultPermissionRaw, SharePermission.viewOnly.rawValue)
        XCTAssertEqual(meta.defaultPermission, .viewOnly)

        meta.defaultPermission = .canMakeChanges
        XCTAssertEqual(meta.defaultPermissionRaw, SharePermission.canMakeChanges.rawValue)
    }

    // MARK: - Feature Flag

    func testFeatureFlagDefaultsToDisabled() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: SharedPinboardsFeatureFlag.key)
        XCTAssertFalse(SharedPinboardsFeatureFlag.isEnabled)
    }

    func testFeatureFlagCanBeEnabled() {
        UserDefaults.standard.set(true, forKey: SharedPinboardsFeatureFlag.key)
        XCTAssertTrue(SharedPinboardsFeatureFlag.isEnabled)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: SharedPinboardsFeatureFlag.key)
    }

    // MARK: - Error Cases

    func testPinboardSharingErrorCases() {
        // Verify all error cases exist
        let errors: [PinboardSharingError] = [
            .featureDisabled,
            .cannotShareLockedPinboard,
            .cannotLockSharedPinboard,
            .insufficientPermission,
            .ownerOnlyOperation,
            .shareNotFound,
            .invalidShareMetadata,
            .sharedZoneSetupFailed,
            .acceptShareFailed,
            .fetchShareDetailsFailed,
            .updateShareSettingsFailed,
            .inviteParticipantFailed,
            .updateParticipantPermissionFailed,
            .removeParticipantFailed,
            .invalidParticipantIdentifier,
            .participantLookupFailed,
            .stopSharingFailed,
            .leaveShareFailed,
        ]
        XCTAssertEqual(errors.count, 18)

        // Verify error descriptions are non-empty
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
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
        pinboard.name = "Test"
        pinboard.colorHex = "#FF0000"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        return pinboard
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
