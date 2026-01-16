import CloudKit
import CoreData
import XCTest

@testable import ClipboardCore

actor MockOutboundCloudDatabase: OutboundCloudDatabase {
    struct Call: Sendable {
        var saved: [CKRecord]
        var deleted: [CKRecord.ID]
    }

    private(set) var calls: [Call] = []
    private var nextResults: [OutboundCloudDatabaseModifyResult] = []

    func resetCalls() {
        calls = []
    }

    func enqueueResults(_ results: [OutboundCloudDatabaseModifyResult]) {
        nextResults.append(contentsOf: results)
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID]
    ) async -> OutboundCloudDatabaseModifyResult {
        calls.append(Call(saved: recordsToSave, deleted: recordIDsToDelete))
        let result = nextResults.isEmpty ? nil : nextResults.removeFirst()
        if let result {
            return result
        }
        return OutboundCloudDatabaseModifyResult(
            savedRecords: recordsToSave, deletedRecordIDs: recordIDsToDelete)
    }
}

final class OutboundSyncEngineTests: XCTestCase {
    private var persistence: PersistenceController!
    private var zoneID: CKRecordZone.ID!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
    }

    override func tearDown() {
        persistence = nil
        zoneID = nil
        super.tearDown()
    }

    func testChangeTrackingCapturesInsertUpdateDelete() async throws {
        let db = MockOutboundCloudDatabase()
        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 2)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let item = makeClipItem(in: context, text: "one")
        let itemID = item.id
        try context.save()
        try await Task.sleep(nanoseconds: 150_000_000)

        let calls1 = await db.calls
        XCTAssertGreaterThanOrEqual(calls1.count, 1)
        XCTAssertTrue(
            calls1[0].saved.contains(where: { $0.recordType == CloudRecordType.clipItem.rawValue }))

        item.primaryText = "two"
        item.modifiedAt = Date()
        try context.save()
        try await Task.sleep(nanoseconds: 150_000_000)

        let calls2 = await db.calls
        XCTAssertGreaterThanOrEqual(calls2.count, 2)
        let lastSavedRecords = calls2.last?.saved ?? []
        let lastItemRecord = lastSavedRecords.first(where: {
            $0.recordType == CloudRecordType.clipItem.rawValue
        })
        XCTAssertEqual(lastItemRecord?.string(for: ClipItemField.primaryText.rawValue), "two")

        context.delete(item)
        try context.save()
        try await Task.sleep(nanoseconds: 150_000_000)

        let calls3 = await db.calls
        XCTAssertGreaterThanOrEqual(calls3.count, 3)
        let expectedDeleteID = CKRecord.ID.clipItemID(itemID, zoneID: zoneID)
        XCTAssertTrue(calls3.last?.deleted.contains(expectedDeleteID) ?? false)
    }

    func testBatchingLogicDebouncesIntoSingleModifyCall() async throws {
        let db = MockOutboundCloudDatabase()
        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.1, retryBackoff: 0.01, maxRetries: 1)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        _ = makeClipItem(in: context, text: "a")
        try context.save()
        _ = makeClipItem(in: context, text: "b")
        try context.save()

        try await Task.sleep(nanoseconds: 250_000_000)

        let calls = await db.calls
        XCTAssertEqual(calls.count, 1)
        let itemRecords = calls[0].saved.filter {
            $0.recordType == CloudRecordType.clipItem.rawValue
        }
        XCTAssertEqual(itemRecords.count, 2)
    }

    func testUploadRetriesOnTransientError() async throws {
        let db = MockOutboundCloudDatabase()
        await db.enqueueResults([
            OutboundCloudDatabaseModifyResult(operationError: CKError(.networkFailure)),
            OutboundCloudDatabaseModifyResult(),
        ])

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 2)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        _ = makeClipItem(in: context, text: "retry")
        try context.save()

        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await db.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testDeletionPropagationIncludesCascadingChildren() async throws {
        let db = MockOutboundCloudDatabase()
        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 1)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let item = makeClipItem(in: context, text: "parent")
        let rep = makeRepresentation(for: item, in: context)
        let preview = makeLinkPreview(for: item, in: context)
        let itemID = item.id
        let repID = rep.id
        let previewID = preview.id
        try context.save()
        try await Task.sleep(nanoseconds: 150_000_000)

        await db.resetCalls()

        context.delete(item)
        try context.save()
        try await Task.sleep(nanoseconds: 150_000_000)

        let calls = await db.calls
        XCTAssertEqual(calls.count, 1)
        let deleted = Set(calls[0].deleted)
        XCTAssertTrue(deleted.contains(.clipItemID(itemID, zoneID: zoneID)))
        XCTAssertTrue(deleted.contains(.clipRepresentationID(repID, zoneID: zoneID)))
        XCTAssertTrue(deleted.contains(.linkPreviewID(previewID, zoneID: zoneID)))
    }

    func testConflictDuringUploadUsesResolverAndRetries() async throws {
        let db = MockOutboundCloudDatabase()

        let serverRecord = CKRecord.clipItem(id: UUID(), zoneID: zoneID)
        serverRecord.setUUID(serverRecord.recordID.extractUUID(), for: ClipItemField.id.rawValue)
        serverRecord.setDate(Date(), for: ClipItemField.createdAt.rawValue)
        serverRecord.setDate(Date(), for: ClipItemField.modifiedAt.rawValue)
        serverRecord.setString("server", for: ClipItemField.contentHash.rawValue)
        serverRecord.setItemType(.text, for: ClipItemField.itemType.rawValue)

        let conflictError = CKError(
            .serverRecordChanged,
            userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord]
        )

        await db.enqueueResults([
            OutboundCloudDatabaseModifyResult(saveErrors: [serverRecord.recordID: conflictError]),
            OutboundCloudDatabaseModifyResult(),
        ])

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 2)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let item = makeClipItem(
            in: context, id: serverRecord.recordID.extractUUID()!, text: "local")
        item.contentHash = "localhash"
        try context.save()

        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await db.calls
        XCTAssertEqual(calls.count, 2)
    }
}

private func makeClipItem(in context: NSManagedObjectContext, id: UUID = UUID(), text: String)
    -> ClipItem
{
    let item =
        NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as! ClipItem
    item.id = id
    item.createdAt = Date()
    item.modifiedAt = Date()
    item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
    item.itemTypeValue = .text
    item.primaryText = text
    item.customTitle = nil
    item.searchableText = text
    item.contentHash = "hash-\(UUID().uuidString)"
    item.isSensitive = false
    item.isTransient = false
    item.needsLinkPreview = false
    item.thumbnailPath = nil
    item.byteCount = Int64(text.utf8.count)
    item.isUserCreated = true
    item.isPinned = false
    return item
}

private func makeRepresentation(for item: ClipItem, in context: NSManagedObjectContext)
    -> ClipRepresentation
{
    let rep =
        NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context)
        as! ClipRepresentation
    rep.id = UUID()
    rep.uti = "public.utf8-plain-text"
    rep.kindValue = .plainText
    rep.displayOrder = 0
    rep.textData = Data((item.primaryText ?? "").utf8)
    rep.byteCount = Int64(rep.textData?.count ?? 0)
    rep.clipItem = item
    return rep
}

private func makeLinkPreview(for item: ClipItem, in context: NSManagedObjectContext) -> LinkPreview
{
    let preview =
        NSEntityDescription.insertNewObject(forEntityName: "LinkPreview", into: context)
        as! LinkPreview
    preview.id = UUID()
    preview.url = "https://example.com"
    preview.title = "Example"
    preview.summary = "Summary"
    preview.imageURL = nil
    preview.imagePath = nil
    preview.siteName = "Example"
    preview.fetchedAt = Date()
    preview.fetchFailed = false
    preview.clipItem = item
    item.linkPreview = preview
    return preview
}
