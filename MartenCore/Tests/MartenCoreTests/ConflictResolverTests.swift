import CloudKit
import XCTest
@testable import MartenCore

final class ConflictResolverTests: XCTestCase {
    func testLastWriterWinsPrefersLaterModifiedAt() {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

        let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let remoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let local = CKRecord.pinboard(id: localID, zoneID: zoneID)
        let remote = CKRecord.pinboard(id: remoteID, zoneID: zoneID)

        let now = Date()
        local.setDate(now.addingTimeInterval(-10), for: PinboardField.modifiedAt.rawValue)
        remote.setDate(now, for: PinboardField.modifiedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolveLastWriterWins(
            local: local,
            remote: remote,
            modifiedAtKey: PinboardField.modifiedAt.rawValue
        )

        XCTAssertEqual(resolution, .keepRemote)
    }

    func testLastWriterWinsTieBreaksByRecordName() {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

        let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let remoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let local = CKRecord.pinboard(id: localID, zoneID: zoneID)
        let remote = CKRecord.pinboard(id: remoteID, zoneID: zoneID)

        let same = Date()
        local.setDate(same, for: PinboardField.modifiedAt.rawValue)
        remote.setDate(same, for: PinboardField.modifiedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolveLastWriterWins(
            local: local,
            remote: remote,
            modifiedAtKey: PinboardField.modifiedAt.rawValue
        )

        XCTAssertEqual(resolution, .keepLocal)
    }

    func testClipItemAppendOnlyPrefersEarlierCreatedAt() {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let local = CKRecord.clipItem(id: id, zoneID: zoneID)
        let remote = CKRecord.clipItem(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now.addingTimeInterval(-100), for: ClipItemField.createdAt.rawValue)
        remote.setDate(now, for: ClipItemField.createdAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolveClipItemAppendOnly(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepLocal)
    }

    func testDeletedWinsDeletesIfEitherDeleted() {
        let resolver = ConflictResolver()
        XCTAssertEqual(resolver.resolveDeletedWins(localIsDeleted: true, remoteIsDeleted: false), .deleteRecord)
        XCTAssertEqual(resolver.resolveDeletedWins(localIsDeleted: false, remoteIsDeleted: true), .deleteRecord)
        XCTAssertEqual(resolver.resolveDeletedWins(localIsDeleted: false, remoteIsDeleted: false), .keepRecord)
    }
}

