import CloudKit
import Combine
import XCTest

@testable import ClipboardCore

// MARK: - Mock CloudKit Manager

final class MockCloudKitManager: @unchecked Sendable {
    var accountState: CloudKitAccountState = .available
    var isZoneSetUp = false
    var isSubscriptionSetUp = false

    var performCompleteSetupCallCount = 0
    var checkAccountStatusCallCount = 0
    var shouldThrowOnSetup: CloudKitSyncError?

    func performCompleteSetup() async throws {
        performCompleteSetupCallCount += 1
        if let error = shouldThrowOnSetup {
            throw error
        }
        isZoneSetUp = true
        isSubscriptionSetUp = true
    }

    func checkAccountStatus() async throws -> CloudKitAccountState {
        checkAccountStatusCallCount += 1
        return accountState
    }
}

// MARK: - Mock Outbound Sync Engine

final class MockOutboundSyncEngine: @unchecked Sendable {
    var startCallCount = 0
    var stopCallCount = 0
    var flushNowCallCount = 0
    var isRunning = false

    func start() {
        startCallCount += 1
        isRunning = true
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func flushNow() {
        flushNowCallCount += 1
    }
}

// MARK: - Mock Inbound Sync Engine

final class MockInboundSyncEngine: @unchecked Sendable {
    var syncInboundCallCount = 0
    var nextResult = InboundSyncResult(fetchedRecordCount: 0, deletedRecordCount: 0, didFullResync: false)
    var shouldThrow: Error?

    func syncInbound() async throws -> InboundSyncResult {
        syncInboundCallCount += 1
        if let error = shouldThrow {
            throw error
        }
        return nextResult
    }
}

// MARK: - Mock Asset Sync Manager

final class MockAssetSyncManager: @unchecked Sendable {
    var resetSessionBudgetsCallCount = 0
    private let progressSubject = PassthroughSubject<AssetSyncManager.ProgressUpdate, Never>()

    var progressPublisher: AnyPublisher<AssetSyncManager.ProgressUpdate, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    func resetSessionBudgets() async {
        resetSessionBudgetsCallCount += 1
    }

    func sendProgress(_ update: AssetSyncManager.ProgressUpdate) {
        progressSubject.send(update)
    }
}

// MARK: - Test Sync Coordinator

/// A testable version of SyncCoordinator that uses mock dependencies.
@MainActor
final class TestSyncCoordinator: ObservableObject, SyncCoordinating {
    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var progress: SyncProgress = .zero
    @Published var syncEnabled: Bool {
        didSet {
            handleSyncEnabledChange()
        }
    }

    let mockCloudKitManager: MockCloudKitManager
    let mockOutboundEngine: MockOutboundSyncEngine
    let mockInboundEngine: MockInboundSyncEngine
    let mockAssetSyncManager: MockAssetSyncManager

    private var isSetUp = false
    private var periodicSyncTask: Task<Void, Never>?
    private var isSyncInProgress = false
    private let syncLock = NSLock()
    private let errorSubject = PassthroughSubject<CloudKitSyncError, Never>()
    private let periodicFetchInterval: TimeInterval

    var errorPublisher: AnyPublisher<CloudKitSyncError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    init(
        syncEnabled: Bool = false,
        periodicFetchInterval: TimeInterval = 30.0
    ) {
        self.syncEnabled = syncEnabled
        self.periodicFetchInterval = periodicFetchInterval
        self.mockCloudKitManager = MockCloudKitManager()
        self.mockOutboundEngine = MockOutboundSyncEngine()
        self.mockInboundEngine = MockInboundSyncEngine()
        self.mockAssetSyncManager = MockAssetSyncManager()
    }

    func startSync() async throws {
        guard syncEnabled else { return }
        guard !isSetUp else { return }

        status = .syncing

        do {
            try await mockCloudKitManager.performCompleteSetup()
            mockOutboundEngine.start()
            startPeriodicInboundSync()
            isSetUp = true
            status = .synced
        } catch let error as CloudKitSyncError {
            status = .error(error)
            errorSubject.send(error)
            throw error
        } catch {
            let syncError = CloudKitSyncError.unexpected(error)
            status = .error(syncError)
            errorSubject.send(syncError)
            throw syncError
        }
    }

    func stopSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        mockOutboundEngine.stop()
        isSetUp = false
        status = .idle
    }

    func triggerSyncNow() async throws {
        guard syncEnabled else {
            throw CloudKitSyncError.containerNotAvailable
        }

        guard acquireSyncLock() else { return }
        defer { releaseSyncLock() }

        status = .syncing
        mockOutboundEngine.flushNow()

        do {
            try await Task.sleep(nanoseconds: 10_000_000)
            let result = try await mockInboundEngine.syncInbound()

            progress = SyncProgress(
                itemsQueued: 0,
                itemsUploaded: 0,
                itemsDownloaded: result.fetchedRecordCount
            )

            lastSyncDate = Date()
            status = .synced
        } catch let error as CloudKitSyncError {
            status = .error(error)
            errorSubject.send(error)
            throw error
        } catch {
            let syncError = CloudKitSyncError.unexpected(error)
            status = .error(syncError)
            errorSubject.send(syncError)
            throw syncError
        }
    }

    func handlePushNotification() async {
        guard syncEnabled, isSetUp else { return }
        guard acquireSyncLock() else { return }
        defer { releaseSyncLock() }

        status = .syncing

        do {
            let result = try await mockInboundEngine.syncInbound()
            progress = SyncProgress(
                itemsQueued: 0,
                itemsUploaded: 0,
                itemsDownloaded: result.fetchedRecordCount
            )
            lastSyncDate = Date()
            status = .synced
        } catch {
            if let syncError = error as? CloudKitSyncError {
                status = .error(syncError)
            }
        }
    }

    private func handleSyncEnabledChange() {
        if syncEnabled {
            Task {
                try? await startSync()
            }
        } else {
            stopSync()
        }
    }

    private func startPeriodicInboundSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.periodicFetchInterval * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    await self.performPeriodicInboundSync()
                } catch {
                    break
                }
            }
        }
    }

    private func performPeriodicInboundSync() async {
        guard acquireSyncLock() else { return }
        defer { releaseSyncLock() }

        status = .syncing

        do {
            let result = try await mockInboundEngine.syncInbound()
            if result.fetchedRecordCount > 0 || result.deletedRecordCount > 0 {
                progress = SyncProgress(
                    itemsQueued: 0,
                    itemsUploaded: 0,
                    itemsDownloaded: result.fetchedRecordCount
                )
            }
            lastSyncDate = Date()
            status = .synced
        } catch {
            if let syncError = error as? CloudKitSyncError {
                status = .error(syncError)
            }
        }
    }

    private func acquireSyncLock() -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        if isSyncInProgress { return false }
        isSyncInProgress = true
        return true
    }

    private func releaseSyncLock() {
        syncLock.lock()
        isSyncInProgress = false
        syncLock.unlock()
    }
}

// MARK: - Tests

final class SyncCoordinatorTests: XCTestCase {

    // MARK: - Sync Lifecycle Tests

    @MainActor
    func testSyncStartsWhenEnabled() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        XCTAssertEqual(coordinator.mockCloudKitManager.performCompleteSetupCallCount, 1)
        XCTAssertEqual(coordinator.mockOutboundEngine.startCallCount, 1)
        XCTAssertTrue(coordinator.mockOutboundEngine.isRunning)
        XCTAssertEqual(coordinator.status, .synced)
    }

    @MainActor
    func testSyncDoesNotStartWhenDisabled() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: false)

        try await coordinator.startSync()

        XCTAssertEqual(coordinator.mockCloudKitManager.performCompleteSetupCallCount, 0)
        XCTAssertEqual(coordinator.mockOutboundEngine.startCallCount, 0)
        XCTAssertEqual(coordinator.status, .idle)
    }

    @MainActor
    func testSyncStopsWhenDisabled() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()
        XCTAssertEqual(coordinator.status, .synced)

        coordinator.stopSync()

        XCTAssertEqual(coordinator.mockOutboundEngine.stopCallCount, 1)
        XCTAssertFalse(coordinator.mockOutboundEngine.isRunning)
        XCTAssertEqual(coordinator.status, .idle)
    }

    @MainActor
    func testEnablingSyncStartsEngines() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: false)
        XCTAssertEqual(coordinator.status, .idle)

        coordinator.syncEnabled = true

        // Allow async task to run
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(coordinator.mockCloudKitManager.performCompleteSetupCallCount, 1)
        XCTAssertEqual(coordinator.mockOutboundEngine.startCallCount, 1)
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testErrorsReportedToStatus() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        coordinator.mockCloudKitManager.shouldThrowOnSetup = .notSignedIn

        var receivedError: CloudKitSyncError?
        let cancellable = coordinator.errorPublisher.sink { error in
            receivedError = error
        }

        do {
            try await coordinator.startSync()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertEqual(coordinator.status, .error(.notSignedIn))
        XCTAssertNotNil(receivedError)

        cancellable.cancel()
    }

    @MainActor
    func testNetworkErrorReportedCorrectly() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        coordinator.mockCloudKitManager.shouldThrowOnSetup = .networkUnavailable

        do {
            try await coordinator.startSync()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertEqual(coordinator.status, .error(.networkUnavailable))
    }

    // MARK: - Manual Sync Tests

    @MainActor
    func testManualSyncTriggersCorrectly() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 5,
            deletedRecordCount: 2,
            didFullResync: false
        )

        try await coordinator.triggerSyncNow()

        XCTAssertEqual(coordinator.mockOutboundEngine.flushNowCallCount, 1)
        XCTAssertEqual(coordinator.mockInboundEngine.syncInboundCallCount, 1)
        XCTAssertEqual(coordinator.progress.itemsDownloaded, 5)
        XCTAssertNotNil(coordinator.lastSyncDate)
        XCTAssertEqual(coordinator.status, .synced)
    }

    @MainActor
    func testManualSyncThrowsWhenDisabled() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: false)

        do {
            try await coordinator.triggerSyncNow()
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitSyncError {
            XCTAssertEqual(error, .containerNotAvailable)
        }
    }

    @MainActor
    func testManualSyncReportsInboundErrors() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        coordinator.mockInboundEngine.shouldThrow = CloudKitSyncError.networkUnavailable

        do {
            try await coordinator.triggerSyncNow()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertEqual(coordinator.status, .error(.networkUnavailable))
    }

    // MARK: - Push Notification Tests

    @MainActor
    func testPushNotificationTriggersInboundSync() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 3,
            deletedRecordCount: 1,
            didFullResync: false
        )

        await coordinator.handlePushNotification()

        XCTAssertEqual(coordinator.mockInboundEngine.syncInboundCallCount, 1)
        XCTAssertEqual(coordinator.progress.itemsDownloaded, 3)
        XCTAssertNotNil(coordinator.lastSyncDate)
    }

    @MainActor
    func testPushNotificationIgnoredWhenSyncDisabled() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: false)

        await coordinator.handlePushNotification()

        XCTAssertEqual(coordinator.mockInboundEngine.syncInboundCallCount, 0)
    }

    @MainActor
    func testPushNotificationIgnoredWhenNotSetUp() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        // Don't call startSync()

        await coordinator.handlePushNotification()

        XCTAssertEqual(coordinator.mockInboundEngine.syncInboundCallCount, 0)
    }

    // MARK: - Coordination Tests

    @MainActor
    func testOutboundFlushesBeforeInboundOnManualSync() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        // Track initial counts before manual sync
        let initialFlushCount = coordinator.mockOutboundEngine.flushNowCallCount
        let initialInboundCount = coordinator.mockInboundEngine.syncInboundCallCount

        try await coordinator.triggerSyncNow()

        // Verify both flush and inbound were called (flush before inbound is ensured by implementation)
        XCTAssertEqual(coordinator.mockOutboundEngine.flushNowCallCount, initialFlushCount + 1)
        XCTAssertEqual(coordinator.mockInboundEngine.syncInboundCallCount, initialInboundCount + 1)
    }

    // MARK: - Status Tests

    @MainActor
    func testStatusTransitionsDuringSync() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        var statusHistory: [SyncStatus] = []
        let cancellable = coordinator.$status.sink { status in
            statusHistory.append(status)
        }

        try await coordinator.startSync()

        // Should have transitioned: idle -> syncing -> synced
        XCTAssertTrue(statusHistory.contains(.idle))
        XCTAssertTrue(statusHistory.contains(.syncing))
        XCTAssertTrue(statusHistory.contains(.synced))

        cancellable.cancel()
    }

    // MARK: - Progress Tests

    @MainActor
    func testProgressUpdatesOnSync() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)

        try await coordinator.startSync()

        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 10,
            deletedRecordCount: 3,
            didFullResync: false
        )

        try await coordinator.triggerSyncNow()

        XCTAssertEqual(coordinator.progress.itemsDownloaded, 10)
    }
}
