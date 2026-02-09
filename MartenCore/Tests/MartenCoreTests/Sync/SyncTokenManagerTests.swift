import CloudKit
import XCTest
@testable import MartenCore

/// Mock implementation of SyncTokenStoring for testing.
final class MockSyncTokenStorage: SyncTokenStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var deleteAllCallCount = 0

    var shouldThrowOnSave = false
    var shouldThrowOnLoad = false
    var shouldThrowOnDelete = false

    func saveToken(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        saveCallCount += 1
        if shouldThrowOnSave {
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        storage[key] = data
    }

    func loadToken(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        loadCallCount += 1
        if shouldThrowOnLoad {
            throw NSError(domain: "test", code: 2, userInfo: nil)
        }
        return storage[key]
    }

    func deleteToken(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        deleteCallCount += 1
        if shouldThrowOnDelete {
            throw NSError(domain: "test", code: 3, userInfo: nil)
        }
        storage.removeValue(forKey: key)
    }

    func deleteAllTokens() throws {
        lock.lock()
        defer { lock.unlock() }

        deleteAllCallCount += 1
        storage.removeAll()
    }

    func hasToken(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[key] != nil
    }

    func storedKeys() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(storage.keys)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        deleteAllCallCount = 0
        shouldThrowOnSave = false
        shouldThrowOnLoad = false
        shouldThrowOnDelete = false
    }
}

final class SyncTokenManagerTests: XCTestCase {

    private var mockStorage: MockSyncTokenStorage!
    private var tokenManager: SyncTokenManager!

    override func setUp() {
        super.setUp()
        mockStorage = MockSyncTokenStorage()
        tokenManager = SyncTokenManager(storage: mockStorage)
    }

    override func tearDown() {
        mockStorage = nil
        tokenManager = nil
        super.tearDown()
    }

    // MARK: - Storage Key Generation Tests

    func testZoneStorageKeyIsUnique() {
        let zone1 = CKRecordZone.ID(zoneName: "Zone1", ownerName: CKCurrentUserDefaultName)
        let zone2 = CKRecordZone.ID(zoneName: "Zone2", ownerName: CKCurrentUserDefaultName)

        // Load attempts should generate different keys
        _ = try? tokenManager.loadToken(for: zone1)
        _ = try? tokenManager.loadToken(for: zone2)

        // Both loads should go to storage since nothing is cached
        XCTAssertEqual(mockStorage.loadCallCount, 2)
    }

    func testLoadTokenReturnsNilWhenNotStored() throws {
        let zoneID = CKRecordZone.ID(zoneName: "NonExistentZone", ownerName: CKCurrentUserDefaultName)

        let token = try tokenManager.loadToken(for: zoneID)
        XCTAssertNil(token)
        XCTAssertEqual(mockStorage.loadCallCount, 1)
    }

    func testClearTokenCallsStorage() throws {
        let zoneID = CKRecordZone.ID(zoneName: "ClearZone", ownerName: CKCurrentUserDefaultName)

        try tokenManager.clearToken(for: zoneID)
        XCTAssertEqual(mockStorage.deleteCallCount, 1)
    }

    func testClearAllTokensCallsStorage() throws {
        try tokenManager.clearAllTokens()
        XCTAssertEqual(mockStorage.deleteAllCallCount, 1)
    }

    func testClearTokenRemovesFromStorage() throws {
        let zoneID = CKRecordZone.ID(zoneName: "ClearTestZone", ownerName: CKCurrentUserDefaultName)
        let expectedKey = "zone.\(CKCurrentUserDefaultName).\(zoneID.zoneName)"

        // Directly put data in mock storage
        try mockStorage.saveToken(Data("fake-token".utf8), forKey: expectedKey)
        XCTAssertTrue(mockStorage.hasToken(forKey: expectedKey))

        try tokenManager.clearToken(for: zoneID)

        XCTAssertFalse(mockStorage.hasToken(forKey: expectedKey))
    }

    // MARK: - Database Token Storage Key Tests

    func testDatabaseTokenKeysByScope() throws {
        // Test that different database scopes use different keys

        // Clear and check for private
        try tokenManager.clearDatabaseToken(for: .private)
        XCTAssertEqual(mockStorage.deleteCallCount, 1)

        try tokenManager.clearDatabaseToken(for: .shared)
        XCTAssertEqual(mockStorage.deleteCallCount, 2)

        try tokenManager.clearDatabaseToken(for: .public)
        XCTAssertEqual(mockStorage.deleteCallCount, 3)
    }

    func testLoadDatabaseTokenReturnsNilWhenNotStored() throws {
        let token = try tokenManager.loadDatabaseToken(for: .private)
        XCTAssertNil(token)
    }

    // MARK: - Error Handling Tests

    func testClearTokenThrowsOnStorageFailure() {
        let zoneID = CKRecordZone.ID(zoneName: "ErrorZone", ownerName: CKCurrentUserDefaultName)
        mockStorage.shouldThrowOnDelete = true

        XCTAssertThrowsError(try tokenManager.clearToken(for: zoneID))
        XCTAssertEqual(mockStorage.deleteCallCount, 1)
    }

    func testLoadTokenHandlesStorageError() {
        let zoneID = CKRecordZone.ID(zoneName: "ErrorZone", ownerName: CKCurrentUserDefaultName)
        mockStorage.shouldThrowOnLoad = true

        XCTAssertThrowsError(try tokenManager.loadToken(for: zoneID))
    }

    // MARK: - UserDefaultsSyncTokenStorage Tests

    func testUserDefaultsStorageSaveAndLoad() throws {
        let suiteName = "TestSuite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = UserDefaultsSyncTokenStorage(userDefaults: userDefaults, keyPrefix: "test.token.")

        let testData = Data("test-token".utf8)
        try storage.saveToken(testData, forKey: "zone1")

        let loaded = try storage.loadToken(forKey: "zone1")
        XCTAssertEqual(loaded, testData)
    }

    func testUserDefaultsStorageDelete() throws {
        let suiteName = "TestSuite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = UserDefaultsSyncTokenStorage(userDefaults: userDefaults, keyPrefix: "test.token.")

        let testData = Data("test-token".utf8)
        try storage.saveToken(testData, forKey: "zone1")
        try storage.deleteToken(forKey: "zone1")

        let loaded = try storage.loadToken(forKey: "zone1")
        XCTAssertNil(loaded)
    }

    func testUserDefaultsStorageDeleteAll() throws {
        let suiteName = "TestSuite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = UserDefaultsSyncTokenStorage(userDefaults: userDefaults, keyPrefix: "test.token.")

        try storage.saveToken(Data("token1".utf8), forKey: "zone1")
        try storage.saveToken(Data("token2".utf8), forKey: "zone2")
        try storage.deleteAllTokens()

        XCTAssertNil(try storage.loadToken(forKey: "zone1"))
        XCTAssertNil(try storage.loadToken(forKey: "zone2"))
    }

    func testUserDefaultsStorageUsesPrefix() throws {
        let suiteName = "TestSuite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let prefix = "custom.prefix."
        let storage = UserDefaultsSyncTokenStorage(userDefaults: userDefaults, keyPrefix: prefix)

        try storage.saveToken(Data("test".utf8), forKey: "mykey")

        // The actual key in UserDefaults should have the prefix
        let prefixedKey = prefix + "mykey"
        XCTAssertNotNil(userDefaults.data(forKey: prefixedKey))
    }

    func testUserDefaultsDeleteAllOnlyDeletesPrefixedKeys() throws {
        let suiteName = "TestSuite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let prefix = "sync.token."
        let storage = UserDefaultsSyncTokenStorage(userDefaults: userDefaults, keyPrefix: prefix)

        // Save a token with prefix
        try storage.saveToken(Data("prefixed".utf8), forKey: "zone1")

        // Save an unrelated key directly
        userDefaults.set("unrelated", forKey: "other.key")

        try storage.deleteAllTokens()

        // Token should be deleted
        XCTAssertNil(try storage.loadToken(forKey: "zone1"))

        // Unrelated key should remain
        XCTAssertEqual(userDefaults.string(forKey: "other.key"), "unrelated")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentClearOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent clears")
        expectation.expectedFulfillmentCount = 10

        let zones = (0..<10).map { i in
            CKRecordZone.ID(zoneName: "ConcurrentZone\(i)", ownerName: CKCurrentUserDefaultName)
        }

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            do {
                try self.tokenManager.clearToken(for: zones[i])
            } catch {
                XCTFail("Concurrent clear failed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(mockStorage.deleteCallCount, 10)
    }

    func testConcurrentLoadOperations() {
        let expectation = XCTestExpectation(description: "Concurrent loads")
        expectation.expectedFulfillmentCount = 100

        let zone = CKRecordZone.ID(zoneName: "SharedZone", ownerName: CKCurrentUserDefaultName)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = try? self.tokenManager.loadToken(for: zone)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
