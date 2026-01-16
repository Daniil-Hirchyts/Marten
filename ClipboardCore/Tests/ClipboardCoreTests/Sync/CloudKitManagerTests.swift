import CloudKit
import XCTest
@testable import ClipboardCore

/// Mock CloudKit database for testing.
final class MockCloudKitDatabase: CloudKitDatabaseProviding, @unchecked Sendable {
    var savedZones: [CKRecordZone] = []
    var savedSubscriptions: [CKSubscription] = []
    var deletedZoneIDs: [CKRecordZone.ID] = []
    var deletedSubscriptionIDs: [CKSubscription.ID] = []

    var zoneExistsToReturn: CKRecordZone?
    var saveZoneError: Error?
    var deleteZoneError: Error?
    var saveSubscriptionError: Error?
    var deleteSubscriptionError: Error?
    var fetchZoneError: Error?

    // Track call counts
    var saveZoneCallCount = 0
    var deleteZoneCallCount = 0
    var saveSubscriptionCallCount = 0
    var deleteSubscriptionCallCount = 0
    var fetchZoneCallCount = 0

    func save(_ zone: CKRecordZone) async throws -> CKRecordZone {
        saveZoneCallCount += 1
        if let error = saveZoneError {
            throw error
        }
        savedZones.append(zone)
        return zone
    }

    func deleteRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        deleteZoneCallCount += 1
        if let error = deleteZoneError {
            throw error
        }
        deletedZoneIDs.append(zoneID)
        return zoneID
    }

    func save(_ subscription: CKSubscription) async throws -> CKSubscription {
        saveSubscriptionCallCount += 1
        if let error = saveSubscriptionError {
            throw error
        }
        savedSubscriptions.append(subscription)
        return subscription
    }

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID {
        deleteSubscriptionCallCount += 1
        if let error = deleteSubscriptionError {
            throw error
        }
        deletedSubscriptionIDs.append(subscriptionID)
        return subscriptionID
    }

    func recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        fetchZoneCallCount += 1
        if let error = fetchZoneError {
            throw error
        }
        if let zone = zoneExistsToReturn {
            return zone
        }
        throw CKError(.zoneNotFound)
    }
}

/// Mock CloudKit container for testing.
final class MockCloudKitContainer: CloudKitContainerProviding, @unchecked Sendable {
    let mockDatabase: MockCloudKitDatabase

    var accountStatusToReturn: CKAccountStatus = .available
    var accountStatusError: Error?
    var accountStatusCallCount = 0

    init() {
        self.mockDatabase = MockCloudKitDatabase()
    }

    var privateCloudDatabase: CloudKitDatabaseProviding {
        mockDatabase
    }

    func accountStatus() async throws -> CKAccountStatus {
        accountStatusCallCount += 1
        if let error = accountStatusError {
            throw error
        }
        return accountStatusToReturn
    }
}

/// Mock delegate for tracking CloudKitManager callbacks.
final class MockCloudKitManagerDelegate: CloudKitManagerDelegate {
    var accountStateChanges: [CloudKitAccountState] = []
    var encounteredErrors: [CloudKitSyncError] = []
    var zoneSetupResults: [Bool] = []

    func cloudKitManager(_ manager: CloudKitManager, didChangeAccountState state: CloudKitAccountState) {
        accountStateChanges.append(state)
    }

    func cloudKitManager(_ manager: CloudKitManager, didEncounterError error: CloudKitSyncError) {
        encounteredErrors.append(error)
    }

    func cloudKitManager(_ manager: CloudKitManager, didCompleteZoneSetup success: Bool) {
        zoneSetupResults.append(success)
    }
}

final class CloudKitManagerTests: XCTestCase {

    private var mockContainer: MockCloudKitContainer!
    private var mockStorage: MockSyncTokenStorage!
    private var tokenManager: SyncTokenManager!
    private var manager: CloudKitManager!
    private var delegate: MockCloudKitManagerDelegate!

    override func setUp() {
        super.setUp()
        mockContainer = MockCloudKitContainer()
        mockStorage = MockSyncTokenStorage()
        tokenManager = SyncTokenManager(storage: mockStorage)
        delegate = MockCloudKitManagerDelegate()

        manager = CloudKitManager(
            configuration: .default,
            container: mockContainer,
            tokenManager: tokenManager
        )
        manager.delegate = delegate
    }

    override func tearDown() {
        mockContainer = nil
        mockStorage = nil
        tokenManager = nil
        manager = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithDefaultConfiguration() {
        let mgr = CloudKitManager(
            configuration: .default,
            container: mockContainer,
            tokenManager: tokenManager
        )

        XCTAssertEqual(mgr.zoneID.zoneName, "ClipboardZone")
        XCTAssertEqual(mgr.subscriptionID, "clipboard-zone-subscription")
        XCTAssertEqual(mgr.accountState, .unknown)
        XCTAssertFalse(mgr.isZoneSetUp)
        XCTAssertFalse(mgr.isSubscriptionSetUp)
    }

    func testInitializationWithCustomConfiguration() {
        let config = CloudKitConfiguration(
            containerIdentifier: "iCloud.custom.container",
            zoneName: "CustomZone"
        )

        let mgr = CloudKitManager(
            configuration: config,
            container: mockContainer,
            tokenManager: tokenManager
        )

        XCTAssertEqual(mgr.zoneID.zoneName, "CustomZone")
    }

    // MARK: - Account Status Tests

    func testCheckAccountStatusAvailable() async throws {
        mockContainer.accountStatusToReturn = .available

        let state = try await manager.checkAccountStatus()

        XCTAssertEqual(state, .available)
        XCTAssertEqual(manager.accountState, .available)
        XCTAssertEqual(mockContainer.accountStatusCallCount, 1)
        XCTAssertTrue(delegate.accountStateChanges.contains(.checking))
        XCTAssertTrue(delegate.accountStateChanges.contains(.available))
    }

    func testCheckAccountStatusNoAccount() async {
        mockContainer.accountStatusToReturn = .noAccount

        do {
            _ = try await manager.checkAccountStatus()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(manager.accountState, .noAccount)
    }

    func testCheckAccountStatusRestricted() async {
        mockContainer.accountStatusToReturn = .restricted

        do {
            _ = try await manager.checkAccountStatus()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .accountRestricted)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(manager.accountState, .restricted)
    }

    func testCheckAccountStatusTemporarilyUnavailable() async {
        mockContainer.accountStatusToReturn = .temporarilyUnavailable

        do {
            _ = try await manager.checkAccountStatus()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(manager.accountState, .temporarilyUnavailable)
    }

    func testVerifyAccountAvailableSuccess() async throws {
        mockContainer.accountStatusToReturn = .available

        try await manager.verifyAccountAvailable()

        XCTAssertEqual(manager.accountState, .available)
    }

    func testVerifyAccountAvailableThrowsWhenNotAvailable() async {
        mockContainer.accountStatusToReturn = .noAccount

        do {
            try await manager.verifyAccountAvailable()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    // MARK: - Zone Setup Tests

    func testSetupZoneSuccess() async throws {
        mockContainer.accountStatusToReturn = .available

        try await manager.setupZone()

        XCTAssertEqual(mockContainer.mockDatabase.saveZoneCallCount, 1)
        XCTAssertEqual(mockContainer.mockDatabase.savedZones.count, 1)
        XCTAssertEqual(mockContainer.mockDatabase.savedZones.first?.zoneID.zoneName, "ClipboardZone")
        XCTAssertTrue(manager.isZoneSetUp)
        XCTAssertEqual(delegate.zoneSetupResults, [true])
    }

    func testSetupZoneFailsWithNetworkError() async {
        mockContainer.accountStatusToReturn = .available
        mockContainer.mockDatabase.saveZoneError = CKError(.networkUnavailable)

        do {
            try await manager.setupZone()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(manager.isZoneSetUp)
        XCTAssertTrue(delegate.encounteredErrors.contains(.networkUnavailable))
    }

    func testSetupZoneFailsWithQuotaExceeded() async {
        mockContainer.accountStatusToReturn = .available
        mockContainer.mockDatabase.saveZoneError = CKError(.quotaExceeded)

        do {
            try await manager.setupZone()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSetupZoneFailsWhenNotSignedIn() async {
        mockContainer.accountStatusToReturn = .noAccount

        do {
            try await manager.setupZone()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(mockContainer.mockDatabase.saveZoneCallCount, 0)
    }

    func testDeleteZoneSuccess() async throws {
        mockContainer.accountStatusToReturn = .available
        try await manager.setupZone()

        try await manager.deleteZone()

        XCTAssertEqual(mockContainer.mockDatabase.deleteZoneCallCount, 1)
        XCTAssertFalse(manager.isZoneSetUp)
    }

    func testDeleteZoneSucceedsWhenZoneNotFound() async throws {
        mockContainer.mockDatabase.deleteZoneError = CKError(.zoneNotFound)

        try await manager.deleteZone()

        XCTAssertFalse(manager.isZoneSetUp)
    }

    // MARK: - Subscription Setup Tests

    func testSetupSubscriptionSuccess() async throws {
        mockContainer.accountStatusToReturn = .available

        try await manager.setupSubscription()

        XCTAssertEqual(mockContainer.mockDatabase.saveSubscriptionCallCount, 1)
        XCTAssertEqual(mockContainer.mockDatabase.savedSubscriptions.count, 1)
        XCTAssertTrue(manager.isSubscriptionSetUp)
    }

    func testSetupSubscriptionFailsWhenNotSignedIn() async {
        mockContainer.accountStatusToReturn = .noAccount

        do {
            try await manager.setupSubscription()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDeleteSubscriptionSuccess() async throws {
        mockContainer.accountStatusToReturn = .available
        try await manager.setupSubscription()

        try await manager.deleteSubscription()

        XCTAssertEqual(mockContainer.mockDatabase.deleteSubscriptionCallCount, 1)
        XCTAssertFalse(manager.isSubscriptionSetUp)
    }

    func testDeleteSubscriptionSucceedsWhenNotFound() async throws {
        mockContainer.mockDatabase.deleteSubscriptionError = CKError(.unknownItem)

        try await manager.deleteSubscription()

        XCTAssertFalse(manager.isSubscriptionSetUp)
    }

    // MARK: - Complete Setup Tests

    func testPerformCompleteSetup() async throws {
        mockContainer.accountStatusToReturn = .available

        try await manager.performCompleteSetup()

        XCTAssertEqual(manager.accountState, .available)
        XCTAssertTrue(manager.isZoneSetUp)
        XCTAssertTrue(manager.isSubscriptionSetUp)
    }

    func testPerformCompleteSetupStopsOnAccountError() async {
        mockContainer.accountStatusToReturn = .noAccount

        do {
            try await manager.performCompleteSetup()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertFalse(manager.isZoneSetUp)
        XCTAssertFalse(manager.isSubscriptionSetUp)
    }

    func testPerformCompleteSetupStopsOnZoneError() async {
        mockContainer.accountStatusToReturn = .available
        mockContainer.mockDatabase.saveZoneError = CKError(.networkUnavailable)

        do {
            try await manager.performCompleteSetup()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertFalse(manager.isZoneSetUp)
        XCTAssertFalse(manager.isSubscriptionSetUp)
    }

    // MARK: - Zone Verification Tests

    func testVerifyZoneExistsReturnsTrue() async throws {
        mockContainer.mockDatabase.zoneExistsToReturn = CKRecordZone(zoneName: "ClipboardZone")

        let exists = try await manager.verifyZoneExists()

        XCTAssertTrue(exists)
        XCTAssertTrue(manager.isZoneSetUp)
    }

    func testVerifyZoneExistsReturnsFalse() async throws {
        mockContainer.mockDatabase.fetchZoneError = CKError(.zoneNotFound)

        let exists = try await manager.verifyZoneExists()

        XCTAssertFalse(exists)
        XCTAssertFalse(manager.isZoneSetUp)
    }

    // MARK: - Token Management Tests

    func testGetZoneChangeTokenReturnsNilInitially() throws {
        let token = try manager.getZoneChangeToken()
        XCTAssertNil(token)
    }

    func testClearZoneChangeToken() throws {
        try manager.clearZoneChangeToken()
        XCTAssertEqual(mockStorage.deleteCallCount, 1)
    }

    // MARK: - Delegate Tests

    func testDelegateReceivesAccountStateChanges() async throws {
        mockContainer.accountStatusToReturn = .available

        _ = try await manager.checkAccountStatus()

        XCTAssertTrue(delegate.accountStateChanges.contains(.checking))
        XCTAssertTrue(delegate.accountStateChanges.contains(.available))
    }

    func testDelegateReceivesErrors() async {
        mockContainer.accountStatusToReturn = .available
        mockContainer.mockDatabase.saveZoneError = CKError(.networkUnavailable)

        _ = try? await manager.setupZone()

        XCTAssertFalse(delegate.encounteredErrors.isEmpty)
    }

    func testDelegateReceivesZoneSetupSuccess() async throws {
        mockContainer.accountStatusToReturn = .available

        try await manager.setupZone()

        XCTAssertEqual(delegate.zoneSetupResults, [true])
    }
}

// MARK: - CloudKitSyncError Equatable Extension for Testing

extension CloudKitSyncError: Equatable {
    public static func == (lhs: CloudKitSyncError, rhs: CloudKitSyncError) -> Bool {
        switch (lhs, rhs) {
        case (.containerNotAvailable, .containerNotAvailable),
             (.notSignedIn, .notSignedIn),
             (.accountRestricted, .accountRestricted),
             (.accountStatusUnknown, .accountStatusUnknown),
             (.networkUnavailable, .networkUnavailable),
             (.quotaExceeded, .quotaExceeded),
             (.zoneNotFound, .zoneNotFound),
             (.userDeletedZone, .userDeletedZone):
            return true
        case (.zoneCreationFailed, .zoneCreationFailed),
             (.subscriptionSetupFailed, .subscriptionSetupFailed),
             (.fetchChangesFailed, .fetchChangesFailed),
             (.pushChangesFailed, .pushChangesFailed),
             (.unexpected, .unexpected):
            return true
        case (.recordConflict, .recordConflict):
            return true
        case (.partialFailure, .partialFailure):
            return true
        case (.serverRejected(let l), .serverRejected(let r)):
            return l == r
        default:
            return false
        }
    }
}
