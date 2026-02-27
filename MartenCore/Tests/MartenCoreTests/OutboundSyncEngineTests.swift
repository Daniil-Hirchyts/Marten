import CloudKit
import Combine
import CoreData
import XCTest

@testable import MartenCore

actor MockOutboundCloudDatabase: OutboundCloudDatabase {
    struct Call: Sendable {
        var saved: [CKRecord]
        var deleted: [CKRecord.ID]
    }

    private(set) var calls: [Call] = []
    private var nextResults: [OutboundCloudDatabaseModifyResult] = []
    private var artificialDelayNanoseconds: UInt64 = 0

    func resetCalls() {
        calls = []
    }

    func enqueueResults(_ results: [OutboundCloudDatabaseModifyResult]) {
        nextResults.append(contentsOf: results)
    }

    func setArtificialDelay(nanoseconds: UInt64) {
        artificialDelayNanoseconds = nanoseconds
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID]
    ) async -> OutboundCloudDatabaseModifyResult {
        if artificialDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        }
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
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
    }

    override func tearDown() {
        persistence = nil
        zoneID = nil
        cancellables.removeAll()
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

    func testFlushAndAwaitResumesAllConcurrentWaiters() async throws {
        let db = MockOutboundCloudDatabase()
        await db.setArtificialDelay(nanoseconds: 250_000_000)

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 1)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        _ = makeClipItem(in: context, text: "flush-await")
        try context.save()

        let firstDone = expectation(description: "first waiter completed")
        let secondDone = expectation(description: "second waiter completed")

        Task {
            await engine.flushAndAwait()
            firstDone.fulfill()
        }

        Task {
            await engine.flushAndAwait()
            secondDone.fulfill()
        }

        await fulfillment(of: [firstDone, secondDone], timeout: 2.0)
    }

    func testFlushAndAwaitReturnsWhenEngineStops() async throws {
        let db = MockOutboundCloudDatabase()
        await db.setArtificialDelay(nanoseconds: 500_000_000)

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.1, retryBackoff: 0.01, maxRetries: 1)
        )
        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        _ = makeClipItem(in: context, text: "stop-wait")
        try context.save()

        let done = expectation(description: "waiter completed after stop")
        Task {
            await engine.flushAndAwait()
            done.fulfill()
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        engine.stop()

        await fulfillment(of: [done], timeout: 1.5)
    }

    func testCustomPinboardMembershipsAreUploadedAndStaleMembershipsDeleted() async throws {
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
        let pinboardA = makePinboard(in: context, name: "A", isSystem: false)
        let pinboardB = makePinboard(in: context, name: "B", isSystem: false)
        let item = makeClipItem(in: context, text: "membership")
        item.addToPinboards(pinboardA)
        try context.save()
        try await Task.sleep(nanoseconds: 180_000_000)

        let firstCalls = await db.calls
        let firstSaved = firstCalls.flatMap(\.saved)
        let membershipRecord = try XCTUnwrap(
            firstSaved.first(where: { $0.recordType == CloudRecordType.pinboardMembership.rawValue })
        )
        XCTAssertEqual(
            membershipRecord.recordID,
            .membershipID(clipItemID: item.id, pinboardID: pinboardA.id, zoneID: zoneID)
        )
        XCTAssertEqual(
            membershipRecord.uuid(for: PinboardMembershipField.clipItemID.rawValue),
            item.id
        )
        XCTAssertEqual(
            membershipRecord.uuid(for: PinboardMembershipField.pinboardID.rawValue),
            pinboardA.id
        )

        await db.resetCalls()

        item.removeFromPinboards(pinboardA)
        try context.save()
        try await Task.sleep(nanoseconds: 180_000_000)

        let secondCalls = await db.calls
        let deletedIDs = Set(secondCalls.flatMap(\.deleted))
        XCTAssertTrue(
            deletedIDs.contains(
                .membershipID(clipItemID: item.id, pinboardID: pinboardA.id, zoneID: zoneID)
            )
        )
        XCTAssertTrue(
            deletedIDs.contains(
                .membershipID(clipItemID: item.id, pinboardID: pinboardB.id, zoneID: zoneID)
            )
        )
    }

    func testSystemPinboardChangesAreNotUploaded() async throws {
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
        _ = makePinboard(in: context, name: "Marten", isSystem: true)
        try context.save()
        try await Task.sleep(nanoseconds: 180_000_000)

        let calls = await db.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testMembershipBackfillEnqueuesExistingItemMemberships() async throws {
        let context = persistence.viewContext
        let pinboard = makePinboard(in: context, name: "Projects", isSystem: false)
        let item = makeClipItem(in: context, text: "backfill")
        item.addToPinboards(pinboard)
        try context.save()

        let db = MockOutboundCloudDatabase()
        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(debounceInterval: 0.05, retryBackoff: 0.01, maxRetries: 1)
        )
        engine.start()
        defer { engine.stop() }

        await engine.enqueueMembershipBackfillForAllItems()
        await engine.flushAndAwait()

        let calls = await db.calls
        let savedRecords = calls.flatMap(\.saved)
        let membershipRecord = try XCTUnwrap(
            savedRecords.first(where: { $0.recordType == CloudRecordType.pinboardMembership.rawValue })
        )
        XCTAssertEqual(
            membershipRecord.recordID,
            .membershipID(clipItemID: item.id, pinboardID: pinboard.id, zoneID: zoneID)
        )
    }

    func testMissingAssetAttachmentPublishesErrorAndMarksFailedAfterRetries() async throws {
        let db = MockOutboundCloudDatabase()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let assetStore = AssetStore(baseURL: tempDirectory)
        let assetSyncManager = AssetSyncManager(assetStore: assetStore)
        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(
                debounceInterval: 0.01,
                retryBackoff: 0.01,
                maxRetries: 2
            ),
            assetSyncManager: assetSyncManager
        )

        var preparationErrors: [SyncRecordPreparationError] = []
        let preparationErrorsExpectation = expectation(description: "received bounded preparation errors")
        preparationErrorsExpectation.expectedFulfillmentCount = 2
        preparationErrorsExpectation.assertForOverFulfill = true
        engine.preparationErrorPublisher
            .sink { error in
                preparationErrors.append(error)
                preparationErrorsExpectation.fulfill()
            }
            .store(in: &cancellables)

        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let item = makeClipItem(in: context, text: "missing-asset")
        let representation = makeRepresentation(for: item, in: context)
        representation.kindValue = .png
        representation.uti = "public.png"
        representation.fileExtension = "png"
        representation.assetRef = UUID()
        representation.textData = nil
        representation.byteCount = 1024
        let representationRecordID = CKRecord.ID.clipRepresentationID(representation.id, zoneID: zoneID)
        try context.save()

        await fulfillment(of: [preparationErrorsExpectation], timeout: 1.5)
        await engine.flushAndAwait()

        let savedRecords = await db.calls.flatMap(\.saved)
        XCTAssertFalse(
            savedRecords.contains { $0.recordID == representationRecordID },
            "Representation upload must be skipped when asset attachment fails"
        )
        XCTAssertEqual(engine.status(for: representationRecordID), .failed)
        XCTAssertEqual(preparationErrors.count, 2)
        for preparationError in preparationErrors {
            guard
                case .assetAttachmentFailed(
                    engine: let engineName,
                    representationID: let failedRepresentationID,
                    reason: let reason
                ) = preparationError
            else {
                XCTFail("Unexpected preparation error case: \(preparationError)")
                continue
            }
            XCTAssertEqual(engineName, "OutboundSyncEngine")
            XCTAssertEqual(failedRepresentationID, representation.id)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testValidAssetAttachmentUploadsRepresentationWithoutPreparationErrors() async throws {
        let db = MockOutboundCloudDatabase()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let assetStore = AssetStore(baseURL: tempDirectory)
        let payload = Data(repeating: 7, count: 2048)
        let assetRef = try assetStore.store(data: payload, fileExtension: "png")
        let assetSyncManager = AssetSyncManager(assetStore: assetStore)

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(
                debounceInterval: 0.01,
                retryBackoff: 0.01,
                maxRetries: 2
            ),
            assetSyncManager: assetSyncManager
        )

        let unexpectedError = expectation(description: "no preparation error expected")
        unexpectedError.isInverted = true
        engine.preparationErrorPublisher
            .sink { _ in
                unexpectedError.fulfill()
            }
            .store(in: &cancellables)

        engine.start()
        defer { engine.stop() }

        let context = persistence.viewContext
        let item = makeClipItem(in: context, text: "valid-asset")
        let representation = makeRepresentation(for: item, in: context)
        representation.kindValue = .png
        representation.uti = "public.png"
        representation.fileExtension = "png"
        representation.assetRef = assetRef
        representation.textData = nil
        representation.byteCount = Int64(payload.count)
        let representationRecordID = CKRecord.ID.clipRepresentationID(representation.id, zoneID: zoneID)
        try context.save()

        try await Task.sleep(nanoseconds: 250_000_000)
        let savedRecords = await db.calls.flatMap(\.saved)
        let uploadedRepresentation = try XCTUnwrap(
            savedRecords.first(where: { $0.recordID == representationRecordID })
        )
        XCTAssertNotNil(uploadedRepresentation.asset(for: ClipRepresentationField.asset.rawValue))

        await fulfillment(of: [unexpectedError], timeout: 0.2)
    }

    func testAssetRepresentationBackfillEnqueuesAssetBackedRepresentations() async throws {
        let db = MockOutboundCloudDatabase()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let assetStore = AssetStore(baseURL: tempDirectory)
        let payload = Data(repeating: 3, count: 512)
        let assetRef = try assetStore.store(data: payload, fileExtension: "png")
        let assetSyncManager = AssetSyncManager(assetStore: assetStore)

        let context = persistence.viewContext
        let item = makeClipItem(in: context, text: "asset-backfill")
        let representation = makeRepresentation(for: item, in: context)
        representation.kindValue = .png
        representation.uti = "public.png"
        representation.fileExtension = "png"
        representation.assetRef = assetRef
        representation.textData = nil
        representation.byteCount = Int64(payload.count)
        let representationRecordID = CKRecord.ID.clipRepresentationID(representation.id, zoneID: zoneID)
        try context.save()

        let engine = OutboundSyncEngine(
            persistenceController: persistence,
            database: db,
            zoneID: zoneID,
            configuration: .init(
                debounceInterval: 0.01,
                retryBackoff: 0.01,
                maxRetries: 2
            ),
            assetSyncManager: assetSyncManager
        )
        engine.start()
        defer { engine.stop() }

        await db.resetCalls()
        let queuedCount = await engine.enqueueAssetRepresentationBackfill()
        XCTAssertEqual(queuedCount, 1)

        await engine.flushAndAwait()
        let savedRecords = await db.calls.flatMap(\.saved)
        XCTAssertTrue(savedRecords.contains(where: { $0.recordID == representationRecordID }))
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

private func makePinboard(
    in context: NSManagedObjectContext,
    name: String,
    isSystem: Bool
) -> Pinboard {
    let pinboard = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context)
        as! Pinboard
    pinboard.id = UUID()
    pinboard.name = name
    pinboard.colorHex = "#808080"
    pinboard.sortOrder = 0
    pinboard.isSystemMarten = isSystem
    pinboard.createdAt = Date()
    return pinboard
}
