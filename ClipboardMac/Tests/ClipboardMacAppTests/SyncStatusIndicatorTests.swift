import ClipboardCore
import Combine
import XCTest

@testable import ClipboardMac

// MARK: - Mock Sync Coordinator

@MainActor
final class MockSyncCoordinating: ObservableObject, SyncCoordinating {
    @Published var status: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var progress: SyncProgress = .zero
    @Published var syncEnabled: Bool = false

    var startSyncCalled = false
    var stopSyncCalled = false
    var triggerSyncNowCalled = false
    var handlePushNotificationCalled = false

    var triggerSyncNowError: Error?

    func startSync() async throws {
        startSyncCalled = true
    }

    func stopSync() {
        stopSyncCalled = true
    }

    func triggerSyncNow() async throws {
        triggerSyncNowCalled = true
        if let error = triggerSyncNowError {
            throw error
        }
        lastSyncDate = Date()
        status = .synced
    }

    func handlePushNotification() async {
        handlePushNotificationCalled = true
    }
}

// MARK: - SyncStatusIndicator Tests

@MainActor
final class SyncStatusIndicatorTests: XCTestCase {

    // MARK: - Status Display Tests

    func testIdleStatusDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        coordinator.status = .idle

        XCTAssertEqual(coordinator.status, .idle)
    }

    func testSyncingStatusDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        coordinator.status = .syncing

        XCTAssertEqual(coordinator.status, .syncing)
    }

    func testSyncedStatusDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        coordinator.status = .synced
        coordinator.lastSyncDate = Date()

        XCTAssertEqual(coordinator.status, .synced)
        XCTAssertNotNil(coordinator.lastSyncDate)
    }

    func testErrorStatusDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        let error = CloudKitSyncError.networkUnavailable
        coordinator.status = .error(error)

        if case .error(let syncError) = coordinator.status {
            XCTAssertEqual(syncError.localizedDescription, error.localizedDescription)
        } else {
            XCTFail("Expected error status")
        }
    }

    func testNotSignedInErrorDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        let error = CloudKitSyncError.notSignedIn
        coordinator.status = .error(error)

        if case .error(let syncError) = coordinator.status {
            XCTAssertTrue(syncError.requiresUserAction)
        } else {
            XCTFail("Expected error status")
        }
    }

    func testQuotaExceededErrorDisplaysCorrectState() {
        let coordinator = MockSyncCoordinating()
        let error = CloudKitSyncError.quotaExceeded
        coordinator.status = .error(error)

        if case .error(let syncError) = coordinator.status {
            XCTAssertTrue(syncError.requiresUserAction)
        } else {
            XCTFail("Expected error status")
        }
    }

    // MARK: - Sync Toggle Tests

    func testSyncToggleEnablesSync() {
        let coordinator = MockSyncCoordinating()
        XCTAssertFalse(coordinator.syncEnabled)

        coordinator.syncEnabled = true
        XCTAssertTrue(coordinator.syncEnabled)
    }

    func testSyncToggleDisablesSync() {
        let coordinator = MockSyncCoordinating()
        coordinator.syncEnabled = true
        XCTAssertTrue(coordinator.syncEnabled)

        coordinator.syncEnabled = false
        XCTAssertFalse(coordinator.syncEnabled)
    }

    // MARK: - Manual Sync Button Tests

    func testManualSyncButtonTriggersSyncNow() async throws {
        let coordinator = MockSyncCoordinating()
        coordinator.syncEnabled = true

        XCTAssertFalse(coordinator.triggerSyncNowCalled)

        try await coordinator.triggerSyncNow()

        XCTAssertTrue(coordinator.triggerSyncNowCalled)
        XCTAssertEqual(coordinator.status, .synced)
        XCTAssertNotNil(coordinator.lastSyncDate)
    }

    func testManualSyncButtonHandlesError() async {
        let coordinator = MockSyncCoordinating()
        coordinator.syncEnabled = true
        coordinator.triggerSyncNowError = CloudKitSyncError.networkUnavailable

        do {
            try await coordinator.triggerSyncNow()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(coordinator.triggerSyncNowCalled)
            XCTAssertTrue(error is CloudKitSyncError)
        }
    }

    // MARK: - Progress Display Tests

    func testProgressUpdatesCorrectly() {
        let coordinator = MockSyncCoordinating()
        coordinator.status = .syncing
        coordinator.progress = SyncProgress(itemsQueued: 10, itemsUploaded: 3, itemsDownloaded: 2)

        XCTAssertEqual(coordinator.progress.itemsQueued, 10)
        XCTAssertEqual(coordinator.progress.itemsUploaded, 3)
        XCTAssertEqual(coordinator.progress.itemsDownloaded, 2)
    }

    // MARK: - RelativeTimeFormatter Tests

    func testRelativeTimeFormatterJustNow() {
        let date = Date()
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "Just now")
    }

    func testRelativeTimeFormatterOneMinuteAgo() {
        let date = Date().addingTimeInterval(-60)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "1 minute ago")
    }

    func testRelativeTimeFormatterMultipleMinutesAgo() {
        let date = Date().addingTimeInterval(-120)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "2 minutes ago")
    }

    func testRelativeTimeFormatterOneHourAgo() {
        let date = Date().addingTimeInterval(-3600)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "1 hour ago")
    }

    func testRelativeTimeFormatterMultipleHoursAgo() {
        let date = Date().addingTimeInterval(-7200)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "2 hours ago")
    }

    func testRelativeTimeFormatterYesterday() {
        let date = Date().addingTimeInterval(-86400)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "Yesterday")
    }

    func testRelativeTimeFormatterMultipleDaysAgo() {
        let date = Date().addingTimeInterval(-172800)
        let formatted = RelativeTimeFormatter.format(date)
        XCTAssertEqual(formatted, "2 days ago")
    }

    // MARK: - SyncStatus Equality Tests

    func testSyncStatusEquality() {
        XCTAssertEqual(SyncStatus.idle, SyncStatus.idle)
        XCTAssertEqual(SyncStatus.syncing, SyncStatus.syncing)
        XCTAssertEqual(SyncStatus.synced, SyncStatus.synced)

        let error1 = CloudKitSyncError.networkUnavailable
        let error2 = CloudKitSyncError.networkUnavailable
        XCTAssertEqual(SyncStatus.error(error1), SyncStatus.error(error2))

        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.syncing)
        XCTAssertNotEqual(SyncStatus.synced, SyncStatus.error(error1))
    }
}
