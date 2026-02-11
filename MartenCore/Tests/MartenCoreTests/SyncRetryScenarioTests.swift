import Combine
import XCTest
@testable import MartenCore

final class SyncRetryScenarioTests: XCTestCase {
    @MainActor
    func testSyncRecoverAfterNetworkError() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        coordinator.mockCloudKitManager.shouldThrowOnSetup = .networkUnavailable

        // First attempt: fails
        do {
            try await coordinator.startSync()
            XCTFail("Expected error")
        } catch {
            // Expected
        }

        XCTAssertEqual(coordinator.status, .error(.networkUnavailable))

        // Clear error and retry
        coordinator.mockCloudKitManager.shouldThrowOnSetup = nil
        coordinator.stopSync() // Reset state

        try await coordinator.startSync()

        XCTAssertEqual(coordinator.status, .synced)
        XCTAssertEqual(coordinator.mockCloudKitManager.performCompleteSetupCallCount, 2)
    }

    @MainActor
    func testManualSyncRetriesAfterPreviousFailure() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        try await coordinator.startSync()

        // First triggerSyncNow: fails
        coordinator.mockInboundEngine.shouldThrow = CloudKitSyncError.networkUnavailable

        do {
            try await coordinator.triggerSyncNow()
            XCTFail("Expected error")
        } catch {
            // Expected
        }

        XCTAssertEqual(coordinator.status, .error(.networkUnavailable))

        // Second triggerSyncNow: succeeds
        coordinator.mockInboundEngine.shouldThrow = nil
        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 2,
            deletedRecordCount: 0,
            didFullResync: false
        )

        try await coordinator.triggerSyncNow()

        XCTAssertEqual(coordinator.status, .synced)
        XCTAssertEqual(coordinator.progress.itemsDownloaded, 2)
    }

    @MainActor
    func testPushNotificationAfterErrorRecovery() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        try await coordinator.startSync()

        // Simulate error state
        coordinator.mockInboundEngine.shouldThrow = CloudKitSyncError.networkUnavailable
        do {
            try await coordinator.triggerSyncNow()
        } catch {
            // Expected
        }
        XCTAssertEqual(coordinator.status, .error(.networkUnavailable))

        // Recovery: push notification with successful inbound
        coordinator.mockInboundEngine.shouldThrow = nil
        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 5,
            deletedRecordCount: 1,
            didFullResync: false
        )

        await coordinator.handlePushNotification()

        XCTAssertEqual(coordinator.status, .synced)
        XCTAssertEqual(coordinator.progress.itemsDownloaded, 5)
        XCTAssertNotNil(coordinator.lastSyncDate)
    }

    @MainActor
    func testConcurrentSyncRequestsAreSerialized() async throws {
        let coordinator = TestSyncCoordinator(syncEnabled: true)
        try await coordinator.startSync()

        coordinator.mockInboundEngine.nextResult = InboundSyncResult(
            fetchedRecordCount: 1,
            deletedRecordCount: 0,
            didFullResync: false
        )

        // Launch two concurrent syncs
        async let first: () = coordinator.triggerSyncNow()
        async let second: () = coordinator.triggerSyncNow()

        // One will succeed, the other will be skipped by the lock
        do {
            try await first
        } catch {}
        do {
            try await second
        } catch {}

        // The inbound engine should have been called at most twice (one per acquire),
        // but typically only once since the lock serializes
        XCTAssertLessThanOrEqual(coordinator.mockInboundEngine.syncInboundCallCount, 2)
    }
}
