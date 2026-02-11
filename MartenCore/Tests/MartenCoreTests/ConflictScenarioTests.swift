import CloudKit
import XCTest
@testable import MartenCore

final class ConflictScenarioTests: XCTestCase {
    private let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

    func testResolveDispatchesClipItemToAppendOnly() {
        let id = UUID()
        let local = CKRecord.clipItem(id: id, zoneID: zoneID)
        let remote = CKRecord.clipItem(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now.addingTimeInterval(-100), for: ClipItemField.createdAt.rawValue)
        remote.setDate(now, for: ClipItemField.createdAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        // Append-only: earlier creation wins → keepLocal
        XCTAssertEqual(resolution, .keepLocal)
    }

    func testResolveDispatchesPinboardToLastWriterWins() {
        let id = UUID()
        let local = CKRecord.pinboard(id: id, zoneID: zoneID)
        let remote = CKRecord.pinboard(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now.addingTimeInterval(-10), for: PinboardField.modifiedAt.rawValue)
        remote.setDate(now, for: PinboardField.modifiedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepRemote)
    }

    func testResolveDispatchesRepresentationToLastWriterWins() {
        let id = UUID()
        let local = CKRecord.clipRepresentation(id: id, zoneID: zoneID)
        let remote = CKRecord.clipRepresentation(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now, for: ClipRepresentationField.modifiedAt.rawValue)
        remote.setDate(now.addingTimeInterval(-5), for: ClipRepresentationField.modifiedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepLocal)
    }

    func testResolveDispatchesLinkPreviewToLastWriterWins() {
        let id = UUID()
        let local = CKRecord.linkPreview(id: id, zoneID: zoneID)
        let remote = CKRecord.linkPreview(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now.addingTimeInterval(-20), for: LinkPreviewField.fetchedAt.rawValue)
        remote.setDate(now, for: LinkPreviewField.fetchedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepRemote)
    }

    func testResolveDispatchesMembershipToLastWriterWins() {
        let id = UUID()
        let local = CKRecord.pinboardMembership(id: id, zoneID: zoneID)
        let remote = CKRecord.pinboardMembership(id: id, zoneID: zoneID)

        let now = Date()
        local.setDate(now, for: PinboardMembershipField.modifiedAt.rawValue)
        remote.setDate(now.addingTimeInterval(-3), for: PinboardMembershipField.modifiedAt.rawValue)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepLocal)
    }

    func testPolicyForAllRecordTypes() {
        let resolver = ConflictResolver()

        XCTAssertEqual(resolver.policy(for: .clipItem), .clipItemAppendOnly)
        XCTAssertEqual(
            resolver.policy(for: .pinboard),
            .lastWriterWins(modifiedAtKey: PinboardField.modifiedAt.rawValue)
        )
        XCTAssertEqual(
            resolver.policy(for: .clipRepresentation),
            .lastWriterWins(modifiedAtKey: ClipRepresentationField.modifiedAt.rawValue)
        )
        XCTAssertEqual(
            resolver.policy(for: .linkPreview),
            .lastWriterWins(modifiedAtKey: LinkPreviewField.fetchedAt.rawValue)
        )
        XCTAssertEqual(
            resolver.policy(for: .pinboardMembership),
            .lastWriterWins(modifiedAtKey: PinboardMembershipField.modifiedAt.rawValue)
        )
    }

    func testResolveWithUnknownRecordTypeDefaultsToKeepRemote() {
        // Create a record with a non-standard type that won't map to CloudRecordType
        let recordID = CKRecord.ID(recordName: "unknown-\(UUID())", zoneID: zoneID)
        let local = CKRecord(recordType: "CKUnknownFutureType", recordID: recordID)
        let remote = CKRecord(recordType: "CKUnknownFutureType", recordID: recordID)

        let resolver = ConflictResolver()
        let resolution = resolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolution, .keepRemote)
    }

    func testMissingModifiedAtFieldDefaultsToKeepRemote() {
        let id = UUID()
        let local = CKRecord.pinboard(id: id, zoneID: zoneID)
        let remote = CKRecord.pinboard(id: id, zoneID: zoneID)

        // Don't set any modifiedAt dates
        let resolver = ConflictResolver()
        let resolution = resolver.resolveLastWriterWins(
            local: local,
            remote: remote,
            modifiedAtKey: PinboardField.modifiedAt.rawValue
        )

        XCTAssertEqual(resolution, .keepRemote)
    }
}
