import CloudKit
import Combine
import CoreData
import XCTest

@testable import MartenCore

final class AssetSyncManagerTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testUploadAttachesCKAssetCorrectly() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let assetStore = AssetStore(baseURL: tempDir)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        let assetRef = try assetStore.store(
            data: Data(repeating: 7, count: 1024), fileExtension: "bin")
        let repID = UUID()

        let rep: ClipRepresentation = try context.performAndWaitThrowing {
            guard
                let obj = NSEntityDescription.insertNewObject(
                    forEntityName: "ClipRepresentation",
                    into: context
                ) as? ClipRepresentation
            else {
                throw NSError(domain: "test", code: 1)
            }
            obj.id = repID
            obj.uti = "public.data"
            obj.kindValue = .png
            obj.displayOrder = 0
            obj.byteCount = 1024
            obj.assetRef = assetRef
            obj.fileExtension = "bin"
            return obj
        }

        let manager = AssetSyncManager(assetStore: assetStore)
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord.clipRepresentation(id: repID, zoneID: zoneID)

        try await manager.attachAssetIfNeeded(from: rep, to: record)

        let attached = try XCTUnwrap(record.asset(for: ClipRepresentationField.asset.rawValue))
        XCTAssertEqual(
            attached.fileURL?.path, assetStore.urlForAsset(assetRef, fileExtension: "bin").path)

        try? fileManager.removeItem(at: tempDir)
    }

    func testApplyDownloadedAssetStoresInAssetStore() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let assetStore = AssetStore(baseURL: tempDir)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        let remoteTempFile = tempDir.appendingPathComponent("remote.bin")
        let remoteData = Data(repeating: 5, count: 2048)
        try remoteData.write(to: remoteTempFile)

        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let repID = UUID()
        let record = CKRecord.clipRepresentation(id: repID, zoneID: zoneID)
        record.setAsset(
            CKAsset(fileURL: remoteTempFile), for: ClipRepresentationField.asset.rawValue)

        let rep: ClipRepresentation = try context.performAndWaitThrowing {
            guard
                let obj = NSEntityDescription.insertNewObject(
                    forEntityName: "ClipRepresentation",
                    into: context
                ) as? ClipRepresentation
            else {
                throw NSError(domain: "test", code: 2)
            }
            obj.id = repID
            obj.uti = "public.data"
            obj.kindValue = .png
            obj.displayOrder = 0
            obj.byteCount = 2048
            obj.fileExtension = "bin"
            return obj
        }

        let manager = AssetSyncManager(assetStore: assetStore)
        try await manager.applyDownloadedAssetIfPresent(from: record, to: rep)

        let storedRef = try XCTUnwrap(rep.assetRef)
        let storedURL = assetStore.urlForAsset(storedRef, fileExtension: rep.fileExtension)
        XCTAssertTrue(fileManager.fileExists(atPath: storedURL.path))
        XCTAssertEqual(try Data(contentsOf: storedURL), remoteData)

        try? fileManager.removeItem(at: tempDir)
    }

    func testPerAssetLimitEnforced() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let assetStore = AssetStore(baseURL: tempDir)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        let assetRef = try assetStore.store(
            data: Data(repeating: 1, count: 32), fileExtension: "bin")
        let repID = UUID()
        let rep: ClipRepresentation = try context.performAndWaitThrowing {
            guard
                let obj = NSEntityDescription.insertNewObject(
                    forEntityName: "ClipRepresentation",
                    into: context
                ) as? ClipRepresentation
            else {
                throw NSError(domain: "test", code: 3)
            }
            obj.id = repID
            obj.uti = "public.data"
            obj.kindValue = .png
            obj.displayOrder = 0
            obj.byteCount = 32
            obj.assetRef = assetRef
            obj.fileExtension = "bin"
            return obj
        }

        let manager = AssetSyncManager(
            assetStore: assetStore,
            configuration: AssetSyncManager.Configuration(
                perAssetLimitBytes: 16, totalLimitBytes: 1024)
        )

        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord.clipRepresentation(id: repID, zoneID: zoneID)

        do {
            try await manager.attachAssetIfNeeded(from: rep, to: record)
            XCTFail("Expected per-asset limit error")
        } catch let error as AssetSyncError {
            XCTAssertEqual(error, .assetTooLarge(bytes: 32, limit: 16))
        }

        try? fileManager.removeItem(at: tempDir)
    }

    func testDownloadOnDemandRetriesAndStores() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let assetStore = AssetStore(baseURL: tempDir)
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID.clipRepresentationID(UUID(), zoneID: zoneID)

        let remoteTempFile = tempDir.appendingPathComponent("remote2.bin")
        try Data(repeating: 9, count: 128).write(to: remoteTempFile)

        let record = CKRecord(
            recordType: CloudRecordType.clipRepresentation.rawValue, recordID: recordID)
        record.setAsset(
            CKAsset(fileURL: remoteTempFile), for: ClipRepresentationField.asset.rawValue)

        let fetcher = MockCloudKitFetcher(failuresBeforeSuccess: 2, recordToReturn: record)
        let manager = AssetSyncManager(
            assetStore: assetStore,
            configuration: AssetSyncManager.Configuration(
                maxRetryCount: 3, initialRetryDelayNanoseconds: 1_000_000)
        )

        let storedRef = try await manager.downloadAssetOnDemand(
            recordID: recordID,
            suggestedFileExtension: "bin",
            from: fetcher
        )

        XCTAssertEqual(fetcher.fetchCallCount, 3)
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: assetStore.urlForAsset(storedRef, fileExtension: "bin").path))
        try? fileManager.removeItem(at: tempDir)
    }

    func testCleanupOrphanedAssetsDeletesOldUnreferenced() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let assetStore = AssetStore(baseURL: tempDir)

        let kept = try assetStore.store(data: Data(repeating: 1, count: 10), fileExtension: "bin")
        let orphan = try assetStore.store(data: Data(repeating: 2, count: 10), fileExtension: "bin")

        let orphanURL = assetStore.urlForAsset(orphan, fileExtension: "bin")
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: orphanURL.path)

        let manager = AssetSyncManager(assetStore: assetStore)
        let deleted = try manager.cleanupOrphanedAssets(
            referencedAssetRefs: [kept],
            policy: .week,
            now: Date()
        )

        XCTAssertEqual(deleted, 1)
        XCTAssertTrue(
            fileManager.fileExists(atPath: assetStore.urlForAsset(kept, fileExtension: "bin").path))
        XCTAssertFalse(fileManager.fileExists(atPath: orphanURL.path))

        try? fileManager.removeItem(at: tempDir)
    }

    func testUploadPublishesProgressAndSupportsCancellation() async throws {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord.clipRepresentation(id: UUID(), zoneID: zoneID)
        let manager = AssetSyncManager()
        let modifier = MockCloudKitModifier()

        let progressExpectation = expectation(description: "Progress published")
        manager.progressPublisher
            .sink { update in
                if update.direction == .upload && update.fractionCompleted > 0 {
                    progressExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let task = Task {
            try await manager.upload(records: [record], in: modifier)
        }

        await fulfillment(of: [progressExpectation], timeout: 2)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class MockCloudKitFetcher: CloudKitRecordsFetching, @unchecked Sendable {
    private let failuresBeforeSuccess: Int
    private let recordToReturn: CKRecord
    var fetchCallCount = 0

    init(failuresBeforeSuccess: Int, recordToReturn: CKRecord) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.recordToReturn = recordToReturn
    }

    func fetchRecord(withID recordID: CKRecord.ID, desiredKeys: [String]?) async throws -> CKRecord
    {
        fetchCallCount += 1
        if fetchCallCount <= failuresBeforeSuccess {
            throw CKError(.networkUnavailable)
        }
        return recordToReturn
    }
}

private final class MockCloudKitModifier: CloudKitRecordsModifying, @unchecked Sendable {
    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID]?,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        perRecordProgress: (@Sendable (String, Double) -> Void)?
    ) async throws -> [CKRecord] {
        try Task.checkCancellation()
        if let first = records.first {
            perRecordProgress?(first.recordID.recordName, 0.5)
        }
        try await Task.sleep(nanoseconds: 5_000_000_000)
        try Task.checkCancellation()
        return records
    }
}
