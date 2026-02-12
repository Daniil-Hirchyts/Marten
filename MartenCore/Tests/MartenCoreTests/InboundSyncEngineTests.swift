import CloudKit
import CoreData
import XCTest

@testable import MartenCore

final class InboundSyncEngineTests: XCTestCase {
    final class InMemoryZoneTokenStore: ZoneChangeTokenStoring, @unchecked Sendable {
        var tokenData: Data?
        var loadCallCount = 0
        var saveCallCount = 0
        var clearCallCount = 0

        func load() throws -> Data? {
            loadCallCount += 1
            return tokenData
        }

        func save(_ tokenData: Data) throws {
            saveCallCount += 1
            self.tokenData = tokenData
        }

        func clear() throws {
            clearCallCount += 1
            tokenData = nil
        }
    }

    final class MockZoneChangesFetcher: ZoneChangesFetching, @unchecked Sendable {
        enum Plan {
            case success(events: [Event], finalToken: Data?)
            case failure(Error)
        }

        enum Event {
            case changed(CKRecord)
            case deleted(CKRecord.ID, String)
            case tokenUpdated(Data)
        }

        var plans: [Plan] = []
        var receivedPreviousTokenData: [Data?] = []
        var delayNanoseconds: UInt64 = 0

        func fetchChanges(
            zoneID: CKRecordZone.ID,
            previousServerChangeTokenData: Data?,
            recordChanged: @escaping (CKRecord) throws -> Void,
            recordDeleted: @escaping (CKRecord.ID, String) throws -> Void,
            tokenUpdated: @escaping (Data) throws -> Void
        ) async throws -> Data? {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            receivedPreviousTokenData.append(previousServerChangeTokenData)
            guard !plans.isEmpty else { return nil }
            let plan = plans.removeFirst()

            switch plan {
            case .failure(let error):
                throw error
            case .success(let events, let finalToken):
                for event in events {
                    switch event {
                    case .changed(let record):
                        try recordChanged(record)
                    case .deleted(let id, let type):
                        try recordDeleted(id, type)
                    case .tokenUpdated(let token):
                        try tokenUpdated(token)
                    }
                }
                return finalToken
            }
        }
    }

    func testChangeFetchInsertsNewRecordsAndPersistsToken() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let tokenStore = InMemoryZoneTokenStore()
        let fetcher = MockZoneChangesFetcher()
        let token = Data([0x01])

        let itemID = UUID()
        let record = CKRecord.clipItem(id: itemID, zoneID: zoneID)
        record.setUUID(itemID, for: ClipItemField.id.rawValue)
        record.setDate(Date(), for: ClipItemField.createdAt.rawValue)
        record.setDate(Date(), for: ClipItemField.modifiedAt.rawValue)
        record.setString("hash-1", for: ClipItemField.contentHash.rawValue)
        record.setItemType(.text, for: ClipItemField.itemType.rawValue)

        fetcher.plans = [
            .success(events: [.changed(record), .tokenUpdated(token)], finalToken: token)
        ]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper
        )

        let result = try await engine.syncInbound()
        XCTAssertEqual(result.fetchedRecordCount, 1)
        XCTAssertEqual(result.deletedRecordCount, 0)
        XCTAssertEqual(tokenStore.saveCallCount, 1)

        let context = persistence.viewContext
        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        let items = try context.fetch(request)
        XCTAssertEqual(items.count, 1)
    }

    func testTokenExpirationClearsTokenAndRetriesFullSync() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let tokenStore = InMemoryZoneTokenStore()
        tokenStore.tokenData = Data([0xAA])

        let fetcher = MockZoneChangesFetcher()
        let tokenNew = Data([0xBB])

        let itemID = UUID()
        let record = CKRecord.clipItem(id: itemID, zoneID: zoneID)
        record.setUUID(itemID, for: ClipItemField.id.rawValue)
        record.setDate(Date(), for: ClipItemField.createdAt.rawValue)
        record.setDate(Date(), for: ClipItemField.modifiedAt.rawValue)
        record.setString("hash-2", for: ClipItemField.contentHash.rawValue)
        record.setItemType(.text, for: ClipItemField.itemType.rawValue)

        fetcher.plans = [
            .failure(CKError(.changeTokenExpired)),
            .success(events: [.changed(record)], finalToken: tokenNew),
        ]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper
        )

        _ = try await engine.syncInbound()

        XCTAssertEqual(tokenStore.clearCallCount, 1)
        XCTAssertEqual(fetcher.receivedPreviousTokenData.count, 2)
        XCTAssertNotNil(fetcher.receivedPreviousTokenData[0])
        XCTAssertNil(fetcher.receivedPreviousTokenData[1])
        XCTAssertEqual(tokenStore.saveCallCount, 1)
    }

    func testDeletionRemovesLocalEntity() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let itemID = UUID()
        let context = persistence.viewContext
        let item =
            NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context)
            as! ClipItem
        item.id = itemID
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.contentHash = "hash-delete"
        item.itemType = ItemType.text.rawValue
        try context.save()

        let tokenStore = InMemoryZoneTokenStore()
        let fetcher = MockZoneChangesFetcher()
        let recordID = CKRecord.ID.clipItemID(itemID, zoneID: zoneID)
        fetcher.plans = [
            .success(
                events: [.deleted(recordID, CloudRecordType.clipItem.rawValue)], finalToken: nil)
        ]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper
        )

        _ = try await engine.syncInbound()

        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        let remaining = try context.fetch(request)
        XCTAssertEqual(remaining.count, 0)
    }

    func testFetchTimeoutThrowsFetchChangesFailedError() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let tokenStore = InMemoryZoneTokenStore()
        let fetcher = MockZoneChangesFetcher()
        fetcher.delayNanoseconds = 500_000_000
        fetcher.plans = [.success(events: [], finalToken: nil)]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper,
            fetchTimeout: 0.1
        )

        do {
            _ = try await engine.syncInbound()
            XCTFail("Expected sync inbound to fail with timeout")
        } catch let error as CloudKitSyncError {
            switch error {
            case .fetchChangesFailed(let underlyingError):
                XCTAssertTrue(underlyingError.localizedDescription.contains("timed out"))
            default:
                XCTFail("Expected fetchChangesFailed, got \(error)")
            }
        }

        XCTAssertEqual(tokenStore.saveCallCount, 0)
    }

    func testMembershipDeletionRemovesLocalPinboardRelationship() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let context = persistence.viewContext
        let item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as! ClipItem
        item.id = UUID()
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
        item.primaryText = "membership delete"
        item.searchableText = "membership delete"
        item.contentHash = "membership-delete-hash"
        item.itemTypeValue = .text
        item.isSensitive = false
        item.isTransient = false
        item.isPinned = false
        item.byteCount = 0
        item.needsLinkPreview = false
        item.isUserCreated = true

        let pinboard = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
        pinboard.id = UUID()
        pinboard.name = "Work"
        pinboard.colorHex = "#123456"
        pinboard.sortOrder = 1
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        item.addToPinboards(pinboard)
        try context.save()

        let membershipRecordID = CKRecord.ID.membershipID(
            clipItemID: item.id,
            pinboardID: pinboard.id,
            zoneID: zoneID
        )

        let tokenStore = InMemoryZoneTokenStore()
        let fetcher = MockZoneChangesFetcher()
        fetcher.plans = [
            .success(
                events: [.deleted(membershipRecordID, CloudRecordType.pinboardMembership.rawValue)],
                finalToken: nil
            )
        ]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper
        )

        _ = try await engine.syncInbound()

        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
        request.fetchLimit = 1
        let refreshed = try XCTUnwrap(context.fetch(request).first)
        XCTAssertFalse(refreshed.pinboards?.contains(where: { $0.id == pinboard.id }) ?? true)
    }

    func testSystemPinboardRecordsAreIgnored() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)
        let persistence = PersistenceController(inMemory: true)
        let mapper = CloudRecordMapper(zoneID: zoneID)

        let tokenStore = InMemoryZoneTokenStore()
        let fetcher = MockZoneChangesFetcher()

        let pinboardID = UUID()
        let record = CKRecord.pinboard(id: pinboardID, zoneID: zoneID)
        record.setUUID(pinboardID, for: PinboardField.id.rawValue)
        record.setString("Marten", for: PinboardField.name.rawValue)
        record.setString("#808080", for: PinboardField.colorHex.rawValue)
        record.setInt16(0, for: PinboardField.sortOrder.rawValue)
        record.setBool(true, for: PinboardField.isSystemMarten.rawValue)
        record.setDate(Date(), for: PinboardField.createdAt.rawValue)

        fetcher.plans = [
            .success(events: [.changed(record)], finalToken: nil)
        ]

        let engine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: fetcher,
            tokenStore: tokenStore,
            persistenceController: persistence,
            recordMapper: mapper
        )

        _ = try await engine.syncInbound()

        let context = persistence.viewContext
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", pinboardID as CVarArg)
        let pinboards = try context.fetch(request)
        XCTAssertTrue(pinboards.isEmpty)
    }
}
