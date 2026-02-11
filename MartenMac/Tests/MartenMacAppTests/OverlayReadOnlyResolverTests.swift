import CloudKit
import CoreData
import MartenCore
import XCTest

@testable import MartenMac

final class OverlayReadOnlyResolverTests: XCTestCase {
    func testIsReadOnlyReturnsFalseWhenNoSelection() throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboard = try makePinboard(in: persistence.viewContext)

        XCTAssertFalse(
            OverlayReadOnlyResolver.isReadOnly(
                selectedPinboardID: nil,
                pinboards: [pinboard]
            )
        )
    }

    func testIsReadOnlyReturnsFalseForPrivatePinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboard = try makePinboard(in: persistence.viewContext)

        XCTAssertFalse(
            OverlayReadOnlyResolver.isReadOnly(
                selectedPinboardID: pinboard.id,
                pinboards: [pinboard]
            )
        )
    }

    func testIsReadOnlyReturnsTrueForSharedViewOnlyPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let pinboard = try makePinboard(in: context)
        _ = try makeShareMetadata(in: context, pinboard: pinboard, isOwner: false, permission: .viewOnly)
        try context.save()

        XCTAssertTrue(
            OverlayReadOnlyResolver.isReadOnly(
                selectedPinboardID: pinboard.id,
                pinboards: [pinboard]
            )
        )
    }

    private func makePinboard(in context: NSManagedObjectContext) throws -> Pinboard {
        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard",
            into: context
        ) as? Pinboard else {
            throw NSError(domain: "OverlayReadOnlyResolverTests", code: 1)
        }
        pinboard.id = UUID()
        pinboard.name = "Pinboard"
        pinboard.colorHex = "#123456"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        return pinboard
    }

    private func makeShareMetadata(
        in context: NSManagedObjectContext,
        pinboard: Pinboard,
        isOwner: Bool,
        permission: SharePermission
    ) throws -> ShareMetadata {
        guard let metadata = NSEntityDescription.insertNewObject(
            forEntityName: "ShareMetadata",
            into: context
        ) as? ShareMetadata else {
            throw NSError(domain: "OverlayReadOnlyResolverTests", code: 2)
        }
        metadata.id = UUID()
        metadata.shareRecordName = "share-\(UUID().uuidString)"
        metadata.rootRecordName = "root-\(UUID().uuidString)"
        metadata.zoneName = "SharedPinboard-\(UUID().uuidString)"
        metadata.zoneOwnerName = isOwner ? CKCurrentUserDefaultName : "owner"
        metadata.isOwner = isOwner
        metadata.accessControl = .onlyInvited
        metadata.defaultPermission = permission
        metadata.pinboard = pinboard
        return metadata
    }
}
