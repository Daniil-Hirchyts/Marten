import CloudKit
import XCTest

@testable import MartenCore

final class CloudRecordUploadOrderingTests: XCTestCase {
    func testSortedForUploadPlacesParentsBeforeDependentRecords() {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let itemID = UUID()
        let pinboardID = UUID()

        let membershipRecord = CKRecord.pinboardMembership(id: UUID(), zoneID: zoneID)
        membershipRecord.setUUID(itemID, for: PinboardMembershipField.clipItemID.rawValue)
        membershipRecord.setUUID(pinboardID, for: PinboardMembershipField.pinboardID.rawValue)

        let representationRecord = CKRecord.clipRepresentation(id: UUID(), zoneID: zoneID)
        representationRecord.setUUID(itemID, for: ClipRepresentationField.clipItemID.rawValue)

        let previewRecord = CKRecord.linkPreview(id: UUID(), zoneID: zoneID)
        previewRecord.setUUID(itemID, for: LinkPreviewField.clipItemID.rawValue)

        let itemRecord = CKRecord.clipItem(id: itemID, zoneID: zoneID)
        itemRecord.setUUID(itemID, for: ClipItemField.id.rawValue)

        let pinboardRecord = CKRecord.pinboard(id: pinboardID, zoneID: zoneID)
        pinboardRecord.setUUID(pinboardID, for: PinboardField.id.rawValue)

        let ordered = CloudRecordUploadOrdering.sortedForUpload([
            membershipRecord,
            representationRecord,
            previewRecord,
            itemRecord,
            pinboardRecord,
        ])

        XCTAssertEqual(
            ordered.map(\.recordType),
            [
                CloudRecordType.pinboard.rawValue,
                CloudRecordType.clipItem.rawValue,
                CloudRecordType.clipRepresentation.rawValue,
                CloudRecordType.linkPreview.rawValue,
                CloudRecordType.pinboardMembership.rawValue,
            ]
        )
    }
}
