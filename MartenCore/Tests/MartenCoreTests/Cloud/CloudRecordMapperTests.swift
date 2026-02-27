import CloudKit
import CoreData
import XCTest

@testable import MartenCore

final class CloudRecordMapperTests: XCTestCase {

    private var persistence: PersistenceController!
    private var mapper: CloudRecordMapper!
    private var zoneID: CKRecordZone.ID!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        mapper = CloudRecordMapper(zoneID: zoneID)
    }

    override func tearDown() {
        persistence = nil
        mapper = nil
        zoneID = nil
        super.tearDown()
    }

    // MARK: - ClipItem Mapping Tests

    func testClipItemToRecord() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)

        let record = mapper.mapToRecord(item)

        XCTAssertEqual(record.recordType, CloudRecordType.clipItem.rawValue)
        XCTAssertEqual(record.uuid(for: ClipItemField.id.rawValue), item.id)
        XCTAssertEqual(record.date(for: ClipItemField.createdAt.rawValue), item.createdAt)
        XCTAssertEqual(record.date(for: ClipItemField.modifiedAt.rawValue), item.modifiedAt)
        XCTAssertEqual(record.string(for: ClipItemField.sourceAppBundleID.rawValue), "com.test.app")
        XCTAssertEqual(record.string(for: ClipItemField.sourceAppName.rawValue), "Test App")
        XCTAssertEqual(
            record.data(for: ClipItemField.sourceAppIconData.rawValue),
            Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        XCTAssertEqual(record.itemType(for: ClipItemField.itemType.rawValue), .text)
        XCTAssertEqual(record.string(for: ClipItemField.primaryText.rawValue), "Test content")
        XCTAssertEqual(record.string(for: ClipItemField.contentHash.rawValue), "testhash123")
        XCTAssertEqual(record.bool(for: ClipItemField.isSensitive.rawValue), false)
        XCTAssertEqual(record.bool(for: ClipItemField.isTransient.rawValue), false)
        XCTAssertEqual(record.bool(for: ClipItemField.isPinned.rawValue), true)
        XCTAssertEqual(record.int64(for: ClipItemField.byteCount.rawValue), 100)
    }

    func testClipItemFromRecord() throws {
        let context = persistence.viewContext
        let record = createTestClipItemRecord()

        let item = try mapper.createClipItem(from: record, in: context)

        XCTAssertEqual(item.id.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(item.sourceAppBundleID, "com.remote.app")
        XCTAssertEqual(item.sourceAppName, "Remote App")
        XCTAssertEqual(item.sourceAppIconData, Data([0xAA, 0xBB, 0xCC]))
        XCTAssertEqual(item.itemTypeValue, .url)
        XCTAssertEqual(item.primaryText, "https://example.com")
        XCTAssertEqual(item.contentHash, "remotehash456")
        XCTAssertTrue(item.isSensitive)
        XCTAssertFalse(item.isTransient)
        XCTAssertFalse(item.isPinned)
        XCTAssertEqual(item.byteCount, 200)
    }

    func testClipItemRoundTrip() throws {
        let context = persistence.viewContext
        let original = createTestClipItem(in: context)
        original.isSensitive = true
        original.isTransient = true

        let record = mapper.mapToRecord(original)
        let restored = try mapper.createClipItem(from: record, in: context)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.sourceAppBundleID, original.sourceAppBundleID)
        XCTAssertEqual(restored.sourceAppName, original.sourceAppName)
        XCTAssertEqual(restored.sourceAppIconData, original.sourceAppIconData)
        XCTAssertEqual(restored.itemTypeValue, original.itemTypeValue)
        XCTAssertEqual(restored.primaryText, original.primaryText)
        XCTAssertEqual(restored.contentHash, original.contentHash)
        XCTAssertEqual(restored.isSensitive, original.isSensitive)
        XCTAssertEqual(restored.isTransient, original.isTransient)
        XCTAssertEqual(restored.isPinned, original.isPinned)
        XCTAssertEqual(restored.byteCount, original.byteCount)
    }

    func testClipItemPrimaryTextTruncation() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        item.primaryText = String(repeating: "a", count: 15_000)

        let record = mapper.mapToRecord(item)
        let truncatedText = record.string(for: ClipItemField.primaryText.rawValue) ?? ""

        XCTAssertEqual(truncatedText.count, 10_000)
    }

    func testClipItemMissingRequiredFieldThrows() {
        let context = persistence.viewContext
        let record = CKRecord.clipItem(id: UUID(), zoneID: zoneID)
        // Missing required fields: id, createdAt, modifiedAt, contentHash, itemType

        XCTAssertThrowsError(try mapper.createClipItem(from: record, in: context)) { error in
            guard case CloudRecordMappingError.missingRequiredField = error else {
                XCTFail("Expected missingRequiredField error")
                return
            }
        }
    }

    // MARK: - ClipRepresentation Mapping Tests

    func testClipRepresentationToRecord() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        let representation = createTestRepresentation(for: item, in: context)

        let record = mapper.mapToRecord(representation, parentItemID: item.id)

        XCTAssertEqual(record.recordType, CloudRecordType.clipRepresentation.rawValue)
        XCTAssertEqual(record.uuid(for: ClipRepresentationField.id.rawValue), representation.id)
        XCTAssertEqual(record.uuid(for: ClipRepresentationField.clipItemID.rawValue), item.id)
        XCTAssertEqual(
            record.string(for: ClipRepresentationField.uti.rawValue), "public.utf8-plain-text")
        XCTAssertEqual(
            record.representationKind(for: ClipRepresentationField.kind.rawValue), .plainText)
        XCTAssertEqual(record.int16(for: ClipRepresentationField.displayOrder.rawValue), 0)
        XCTAssertEqual(record.int64(for: ClipRepresentationField.byteCount.rawValue), 50)

        // Verify parent reference is set
        let parentRef = record.reference(for: ClipRepresentationField.clipItemRef.rawValue)
        XCTAssertNotNil(parentRef)
        XCTAssertEqual(parentRef?.recordID.recordName, "ClipItem-\(item.id.uuidString)")
    }

    func testClipRepresentationFromRecord() throws {
        let context = persistence.viewContext
        let record = createTestRepresentationRecord()

        let representation = try mapper.createClipRepresentation(from: record, in: context)

        XCTAssertEqual(representation.id.uuidString, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(representation.uti, "public.html")
        XCTAssertEqual(representation.kindValue, .html)
        XCTAssertEqual(representation.displayOrder, 1)
        XCTAssertEqual(representation.byteCount, 150)

        if let textData = representation.textData,
            let text = String(data: textData, encoding: .utf8)
        {
            XCTAssertEqual(text, "<html><body>Test</body></html>")
        } else {
            XCTFail("textData should be set")
        }
    }

    func testClipRepresentationRoundTrip() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        let original = createTestRepresentation(for: item, in: context)

        let record = mapper.mapToRecord(original, parentItemID: item.id)
        let restored = try mapper.createClipRepresentation(from: record, in: context)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.uti, original.uti)
        XCTAssertEqual(restored.kindValue, original.kindValue)
        XCTAssertEqual(restored.displayOrder, original.displayOrder)
        XCTAssertEqual(restored.byteCount, original.byteCount)
    }

    // MARK: - Pinboard Mapping Tests

    func testPinboardToRecord() throws {
        let context = persistence.viewContext
        let pinboard = createTestPinboard(in: context)

        let record = mapper.mapToRecord(pinboard)

        XCTAssertEqual(record.recordType, CloudRecordType.pinboard.rawValue)
        XCTAssertEqual(record.uuid(for: PinboardField.id.rawValue), pinboard.id)
        XCTAssertEqual(record.string(for: PinboardField.name.rawValue), "Test Pinboard")
        XCTAssertEqual(record.string(for: PinboardField.colorHex.rawValue), "#FF5733")
        XCTAssertEqual(record.int16(for: PinboardField.sortOrder.rawValue), 0)
        XCTAssertFalse(record.bool(for: PinboardField.isSystemMarten.rawValue))
        XCTAssertNotNil(record.date(for: PinboardField.createdAt.rawValue))
        XCTAssertEqual(record.string(for: PinboardField.iconName.rawValue), "star.fill")
        XCTAssertEqual(record.string(for: PinboardField.shareToken.rawValue), "token-test-value")
    }

    func testPinboardFromRecord() throws {
        let context = persistence.viewContext
        let record = createTestPinboardRecord()

        let pinboard = try mapper.createPinboard(from: record, in: context)

        XCTAssertEqual(pinboard.id.uuidString, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(pinboard.name, "Remote Pinboard")
        XCTAssertEqual(pinboard.colorHex, "#3498DB")
        XCTAssertEqual(pinboard.sortOrder, 5)
        XCTAssertFalse(pinboard.isSystemMarten)
        XCTAssertEqual(pinboard.iconName, "folder.fill")
        XCTAssertEqual(pinboard.shareToken, "token-remote-value")
    }

    func testPinboardRoundTrip() throws {
        let context = persistence.viewContext
        let original = createTestPinboard(in: context)

        let record = mapper.mapToRecord(original)
        let restored = try mapper.createPinboard(from: record, in: context)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.colorHex, original.colorHex)
        XCTAssertEqual(restored.sortOrder, original.sortOrder)
        XCTAssertEqual(restored.isSystemMarten, original.isSystemMarten)
        XCTAssertEqual(restored.iconName, original.iconName)
        XCTAssertEqual(restored.shareToken, original.shareToken)
    }

    // MARK: - PinboardMembership Mapping Tests

    func testPinboardMembershipToRecord() {
        let membership = CloudRecordMapper.PinboardMembershipData(
            id: UUID(),
            clipItemID: UUID(),
            pinboardID: UUID(),
            addedAt: Date(),
            modifiedAt: Date()
        )

        let record = mapper.mapToRecord(membership)

        XCTAssertEqual(record.recordType, CloudRecordType.pinboardMembership.rawValue)
        XCTAssertEqual(record.uuid(for: PinboardMembershipField.id.rawValue), membership.id)
        XCTAssertEqual(
            record.uuid(for: PinboardMembershipField.clipItemID.rawValue), membership.clipItemID)
        XCTAssertEqual(
            record.uuid(for: PinboardMembershipField.pinboardID.rawValue), membership.pinboardID)
        XCTAssertNotNil(record.date(for: PinboardMembershipField.addedAt.rawValue))
        XCTAssertNotNil(record.date(for: PinboardMembershipField.modifiedAt.rawValue))
    }

    func testPinboardMembershipFromRecord() throws {
        let record = createTestMembershipRecord()

        let membership = try mapper.createPinboardMembershipData(from: record)

        XCTAssertEqual(membership.id.uuidString, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(membership.clipItemID.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(membership.pinboardID.uuidString, "33333333-3333-3333-3333-333333333333")
    }

    func testPinboardMembershipRoundTrip() throws {
        let original = CloudRecordMapper.PinboardMembershipData(
            id: UUID(),
            clipItemID: UUID(),
            pinboardID: UUID()
        )

        let record = mapper.mapToRecord(original)
        let restored = try mapper.createPinboardMembershipData(from: record)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.clipItemID, original.clipItemID)
        XCTAssertEqual(restored.pinboardID, original.pinboardID)
    }

    // MARK: - LinkPreview Mapping Tests

    func testLinkPreviewToRecord() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        let preview = createTestLinkPreview(for: item, in: context)

        let record = mapper.mapToRecord(preview, parentItemID: item.id)

        XCTAssertEqual(record.recordType, CloudRecordType.linkPreview.rawValue)
        XCTAssertEqual(record.uuid(for: LinkPreviewField.id.rawValue), preview.id)
        XCTAssertEqual(record.uuid(for: LinkPreviewField.clipItemID.rawValue), item.id)
        XCTAssertEqual(record.string(for: LinkPreviewField.url.rawValue), "https://example.com")
        XCTAssertEqual(record.string(for: LinkPreviewField.title.rawValue), "Example Site")
        XCTAssertEqual(record.string(for: LinkPreviewField.summary.rawValue), "A test website")
        XCTAssertEqual(record.string(for: LinkPreviewField.siteName.rawValue), "Example")
        XCTAssertNotNil(record.date(for: LinkPreviewField.fetchedAt.rawValue))

        // Verify parent reference
        let parentRef = record.reference(for: LinkPreviewField.clipItemRef.rawValue)
        XCTAssertNotNil(parentRef)
    }

    func testLinkPreviewFromRecord() throws {
        let context = persistence.viewContext
        let record = createTestLinkPreviewRecord()

        let preview = try mapper.createLinkPreview(from: record, in: context)

        XCTAssertEqual(preview.id.uuidString, "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(preview.url, "https://github.com")
        XCTAssertEqual(preview.title, "GitHub")
        XCTAssertEqual(preview.summary, "Where the world builds software")
        XCTAssertEqual(preview.siteName, "GitHub")
    }

    func testLinkPreviewRoundTrip() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        let original = createTestLinkPreview(for: item, in: context)

        let record = mapper.mapToRecord(original, parentItemID: item.id)
        let restored = try mapper.createLinkPreview(from: record, in: context)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.url, original.url)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.summary, original.summary)
        XCTAssertEqual(restored.siteName, original.siteName)
    }

    // MARK: - Record ID Tests

    func testRecordIDExtractUUID() {
        let uuid = UUID()
        let recordID = CKRecord.ID.clipItemID(uuid, zoneID: zoneID)

        XCTAssertEqual(recordID.extractUUID(), uuid)
    }

    func testRecordIDExtractUUIDInvalid() {
        let recordID = CKRecord.ID(recordName: "invalid-format", zoneID: zoneID)
        XCTAssertNil(recordID.extractUUID())
    }

    // MARK: - Batch Mapping Tests

    func testMapItemWithRepresentations() throws {
        let context = persistence.viewContext
        let item = createTestClipItem(in: context)
        _ = createTestRepresentation(for: item, in: context)
        _ = createTestLinkPreview(for: item, in: context)
        try context.save()

        let records = mapper.mapItemWithRepresentations(item)

        XCTAssertEqual(records.count, 3)  // Item + Representation + LinkPreview

        let recordTypes = records.map { $0.recordType }
        XCTAssertTrue(recordTypes.contains(CloudRecordType.clipItem.rawValue))
        XCTAssertTrue(recordTypes.contains(CloudRecordType.clipRepresentation.rawValue))
        XCTAssertTrue(recordTypes.contains(CloudRecordType.linkPreview.rawValue))
    }

    // MARK: - Parent ID Extraction Tests

    func testExtractParentClipItemIDFromRepresentation() throws {
        let parentID = UUID()
        let record = CKRecord.clipRepresentation(id: UUID(), zoneID: zoneID)
        record.setUUID(parentID, for: ClipRepresentationField.clipItemID.rawValue)

        let extractedID = mapper.extractParentClipItemID(from: record)

        XCTAssertEqual(extractedID, parentID)
    }

    func testExtractParentClipItemIDFromLinkPreview() throws {
        let parentID = UUID()
        let record = CKRecord.linkPreview(id: UUID(), zoneID: zoneID)
        record.setUUID(parentID, for: LinkPreviewField.clipItemID.rawValue)

        let extractedID = mapper.extractParentClipItemID(from: record)

        XCTAssertEqual(extractedID, parentID)
    }

    // MARK: - Record Type Identification Tests

    func testIdentifyRecordType() {
        let clipItemRecord = CKRecord.clipItem(id: UUID(), zoneID: zoneID)
        let representationRecord = CKRecord.clipRepresentation(id: UUID(), zoneID: zoneID)
        let pinboardRecord = CKRecord.pinboard(id: UUID(), zoneID: zoneID)
        let membershipRecord = CKRecord.pinboardMembership(id: UUID(), zoneID: zoneID)
        let linkPreviewRecord = CKRecord.linkPreview(id: UUID(), zoneID: zoneID)

        XCTAssertEqual(mapper.identifyRecordType(clipItemRecord), .clipItem)
        XCTAssertEqual(mapper.identifyRecordType(representationRecord), .clipRepresentation)
        XCTAssertEqual(mapper.identifyRecordType(pinboardRecord), .pinboard)
        XCTAssertEqual(mapper.identifyRecordType(membershipRecord), .pinboardMembership)
        XCTAssertEqual(mapper.identifyRecordType(linkPreviewRecord), .linkPreview)
    }

    func testIdentifyUnknownRecordType() {
        let record = CKRecord(recordType: "UnknownType")
        XCTAssertNil(mapper.identifyRecordType(record))
    }

    // MARK: - Helper Methods

    private func createTestClipItem(in context: NSManagedObjectContext) -> ClipItem {
        let item =
            NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context)
            as! ClipItem
        item.id = UUID()
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
        item.sourceAppBundleID = "com.test.app"
        item.sourceAppName = "Test App"
        item.sourceAppIconData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        item.itemTypeValue = .text
        item.primaryText = "Test content"
        item.contentHash = "testhash123"
        item.isSensitive = false
        item.isTransient = false
        item.isPinned = true
        item.byteCount = 100
        return item
    }

    private func createTestRepresentation(for item: ClipItem, in context: NSManagedObjectContext)
        -> ClipRepresentation
    {
        let representation =
            NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context)
            as! ClipRepresentation
        representation.id = UUID()
        representation.uti = "public.utf8-plain-text"
        representation.kindValue = .plainText
        representation.displayOrder = 0
        representation.textData = Data("Test text data".utf8)
        representation.byteCount = 50
        representation.clipItem = item
        item.addToRepresentations(representation)
        return representation
    }

    private func createTestPinboard(in context: NSManagedObjectContext) -> Pinboard {
        let pinboard =
            NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context)
            as! Pinboard
        pinboard.id = UUID()
        pinboard.name = "Test Pinboard"
        pinboard.colorHex = "#FF5733"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        pinboard.iconName = "star.fill"
        pinboard.shareToken = "token-test-value"
        return pinboard
    }

    private func createTestLinkPreview(for item: ClipItem, in context: NSManagedObjectContext)
        -> LinkPreview
    {
        let preview =
            NSEntityDescription.insertNewObject(forEntityName: "LinkPreview", into: context)
            as! LinkPreview
        preview.id = UUID()
        preview.url = "https://example.com"
        preview.title = "Example Site"
        preview.summary = "A test website"
        preview.siteName = "Example"
        preview.fetchedAt = Date()
        preview.fetchFailed = false
        preview.clipItem = item
        item.linkPreview = preview
        return preview
    }

    private func createTestClipItemRecord() -> CKRecord {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let record = CKRecord.clipItem(id: id, zoneID: zoneID)

        record.setUUID(id, for: ClipItemField.id.rawValue)
        record.setDate(Date(), for: ClipItemField.createdAt.rawValue)
        record.setDate(Date(), for: ClipItemField.modifiedAt.rawValue)
        record.setString("com.remote.app", for: ClipItemField.sourceAppBundleID.rawValue)
        record.setString("Remote App", for: ClipItemField.sourceAppName.rawValue)
        record.setData(Data([0xAA, 0xBB, 0xCC]), for: ClipItemField.sourceAppIconData.rawValue)
        record.setItemType(.url, for: ClipItemField.itemType.rawValue)
        record.setString("https://example.com", for: ClipItemField.primaryText.rawValue)
        record.setString("remotehash456", for: ClipItemField.contentHash.rawValue)
        record.setBool(true, for: ClipItemField.isSensitive.rawValue)
        record.setBool(false, for: ClipItemField.isTransient.rawValue)
        record.setBool(false, for: ClipItemField.isPinned.rawValue)
        record.setInt64(200, for: ClipItemField.byteCount.rawValue)

        return record
    }

    private func createTestRepresentationRecord() -> CKRecord {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let record = CKRecord.clipRepresentation(id: id, zoneID: zoneID)

        record.setUUID(id, for: ClipRepresentationField.id.rawValue)
        record.setUUID(UUID(), for: ClipRepresentationField.clipItemID.rawValue)
        record.setString("public.html", for: ClipRepresentationField.uti.rawValue)
        record.setRepresentationKind(.html, for: ClipRepresentationField.kind.rawValue)
        record.setInt16(1, for: ClipRepresentationField.displayOrder.rawValue)
        record.setString(
            "<html><body>Test</body></html>", for: ClipRepresentationField.textData.rawValue)
        record.setInt64(150, for: ClipRepresentationField.byteCount.rawValue)

        return record
    }

    private func createTestPinboardRecord() -> CKRecord {
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let record = CKRecord.pinboard(id: id, zoneID: zoneID)

        record.setUUID(id, for: PinboardField.id.rawValue)
        record.setString("Remote Pinboard", for: PinboardField.name.rawValue)
        record.setString("#3498DB", for: PinboardField.colorHex.rawValue)
        record.setInt16(5, for: PinboardField.sortOrder.rawValue)
        record.setBool(false, for: PinboardField.isSystemMarten.rawValue)
        record.setDate(Date(), for: PinboardField.createdAt.rawValue)
        record.setString("folder.fill", for: PinboardField.iconName.rawValue)
        record.setString("token-remote-value", for: PinboardField.shareToken.rawValue)

        return record
    }

    private func createTestMembershipRecord() -> CKRecord {
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let record = CKRecord.pinboardMembership(id: id, zoneID: zoneID)

        record.setUUID(id, for: PinboardMembershipField.id.rawValue)
        record.setUUID(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            for: PinboardMembershipField.clipItemID.rawValue)
        record.setUUID(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            for: PinboardMembershipField.pinboardID.rawValue)
        record.setDate(Date(), for: PinboardMembershipField.addedAt.rawValue)
        record.setDate(Date(), for: PinboardMembershipField.modifiedAt.rawValue)

        return record
    }

    private func createTestLinkPreviewRecord() -> CKRecord {
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let record = CKRecord.linkPreview(id: id, zoneID: zoneID)

        record.setUUID(id, for: LinkPreviewField.id.rawValue)
        record.setUUID(UUID(), for: LinkPreviewField.clipItemID.rawValue)
        record.setString("https://github.com", for: LinkPreviewField.url.rawValue)
        record.setString("GitHub", for: LinkPreviewField.title.rawValue)
        record.setString("Where the world builds software", for: LinkPreviewField.summary.rawValue)
        record.setString("GitHub", for: LinkPreviewField.siteName.rawValue)
        record.setDate(Date(), for: LinkPreviewField.fetchedAt.rawValue)

        return record
    }
}

// MARK: - CKRecord Extension Tests

final class CKRecordExtensionsTests: XCTestCase {

    private var zoneID: CKRecordZone.ID!

    override func setUp() {
        super.setUp()
        zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
    }

    override func tearDown() {
        zoneID = nil
        super.tearDown()
    }

    func testStringFieldGetSet() {
        let record = CKRecord(recordType: "Test")
        record.setString("test value", for: "testField")

        XCTAssertEqual(record.string(for: "testField"), "test value")
    }

    func testStringFieldNil() {
        let record = CKRecord(recordType: "Test")
        XCTAssertNil(record.string(for: "nonexistent"))
    }

    func testUUIDFieldGetSet() {
        let record = CKRecord(recordType: "Test")
        let uuid = UUID()
        record.setUUID(uuid, for: "testField")

        XCTAssertEqual(record.uuid(for: "testField"), uuid)
    }

    func testDateFieldGetSet() {
        let record = CKRecord(recordType: "Test")
        let date = Date()
        record.setDate(date, for: "testField")

        XCTAssertEqual(record.date(for: "testField"), date)
    }

    func testInt64FieldGetSet() {
        let record = CKRecord(recordType: "Test")
        record.setInt64(12345, for: "testField")

        XCTAssertEqual(record.int64(for: "testField"), 12345)
    }

    func testInt16FieldGetSet() {
        let record = CKRecord(recordType: "Test")
        record.setInt16(123, for: "testField")

        XCTAssertEqual(record.int16(for: "testField"), 123)
    }

    func testBoolFieldTrue() {
        let record = CKRecord(recordType: "Test")
        record.setBool(true, for: "testField")

        XCTAssertTrue(record.bool(for: "testField"))
    }

    func testBoolFieldFalse() {
        let record = CKRecord(recordType: "Test")
        record.setBool(false, for: "testField")

        XCTAssertFalse(record.bool(for: "testField"))
    }

    func testBoolFieldDefaultFalse() {
        let record = CKRecord(recordType: "Test")

        XCTAssertFalse(record.bool(for: "nonexistent"))
    }

    func testItemTypeFieldGetSet() {
        let record = CKRecord(recordType: "Test")
        record.setItemType(.image, for: "testField")

        XCTAssertEqual(record.itemType(for: "testField"), .image)
    }

    func testRepresentationKindFieldGetSet() {
        let record = CKRecord(recordType: "Test")
        record.setRepresentationKind(.rtf, for: "testField")

        XCTAssertEqual(record.representationKind(for: "testField"), .rtf)
    }

    func testValidateClipItemFieldsComplete() {
        let record = CKRecord.clipItem(id: UUID(), zoneID: zoneID)
        record.setUUID(UUID(), for: ClipItemField.id.rawValue)
        record.setDate(Date(), for: ClipItemField.createdAt.rawValue)
        record.setDate(Date(), for: ClipItemField.modifiedAt.rawValue)
        record.setString("hash", for: ClipItemField.contentHash.rawValue)
        record.setItemType(.text, for: ClipItemField.itemType.rawValue)

        let missingFields = record.validateClipItemFields()

        XCTAssertTrue(missingFields.isEmpty)
    }

    func testValidateClipItemFieldsMissing() {
        let record = CKRecord.clipItem(id: UUID(), zoneID: zoneID)

        let missingFields = record.validateClipItemFields()

        XCTAssertEqual(missingFields.count, 5)
        XCTAssertTrue(missingFields.contains(ClipItemField.id.rawValue))
        XCTAssertTrue(missingFields.contains(ClipItemField.createdAt.rawValue))
        XCTAssertTrue(missingFields.contains(ClipItemField.modifiedAt.rawValue))
        XCTAssertTrue(missingFields.contains(ClipItemField.contentHash.rawValue))
        XCTAssertTrue(missingFields.contains(ClipItemField.itemType.rawValue))
    }
}
