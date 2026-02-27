import Foundation
import MartenCore
import XCTest

@testable import MartenMac

@MainActor
final class PinboardLockControllerTests: XCTestCase {
    func testSetLockEnabledPersistsAndRemovesLockState() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let synchronizer = StubLockStateSynchronizer()

        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer
        )
        let pinboardID = UUID()

        controller.setLockEnabled(true, pinboardID: pinboardID)
        XCTAssertTrue(controller.isLocked(pinboardID: pinboardID))
        XCTAssertFalse(controller.canAccess(pinboardID: pinboardID))

        let storedLocked = Set(
            (defaults.array(forKey: PinboardSecuritySettings.lockedPinboardIDsKey) as? [String])
                ?? []
        )
        XCTAssertEqual(storedLocked, Set([pinboardID.uuidString]))

        controller.setLockEnabled(false, pinboardID: pinboardID)
        XCTAssertFalse(controller.isLocked(pinboardID: pinboardID))
        XCTAssertTrue(controller.canAccess(pinboardID: pinboardID))

        let storedAfterUnlock = (defaults.array(forKey: PinboardSecuritySettings.lockedPinboardIDsKey)
            as? [String]) ?? []
        XCTAssertTrue(storedAfterUnlock.isEmpty)
    }

    func testUnlockExpiresAfterConfiguredDuration() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let synchronizer = StubLockStateSynchronizer()

        defaults.set(1, forKey: PinboardSecuritySettings.unlockDurationSecondsKey)

        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer
        )
        let pinboardID = UUID()
        controller.setLockEnabled(true, pinboardID: pinboardID)

        let didUnlock = await controller.unlock(pinboardID: pinboardID, pinboardName: "Private")
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(controller.canAccess(pinboardID: pinboardID))

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertFalse(controller.canAccess(pinboardID: pinboardID))
    }

    func testReconcileRemovesStalePinboards() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let synchronizer = StubLockStateSynchronizer()

        let staleID = UUID()
        let validID = UUID()
        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer
        )

        controller.setLockEnabled(true, pinboardID: staleID)
        controller.setLockEnabled(true, pinboardID: validID)
        _ = await controller.unlock(pinboardID: staleID, pinboardName: "Old")

        controller.reconcile(validPinboardIDs: [validID])

        XCTAssertFalse(controller.isLocked(pinboardID: staleID))
        XCTAssertTrue(controller.canAccess(pinboardID: staleID))
        XCTAssertTrue(controller.isLocked(pinboardID: validID))

        let storedLocked = Set(
            (defaults.array(forKey: PinboardSecuritySettings.lockedPinboardIDsKey) as? [String])
                ?? []
        )
        XCTAssertEqual(storedLocked, Set([validID.uuidString]))
    }

    func testExternalSyncUpdateReplacesLocalLockedState() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let synchronizer = StubLockStateSynchronizer()

        let first = UUID()
        let second = UUID()
        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer
        )

        controller.setLockEnabled(true, pinboardID: first)
        XCTAssertTrue(controller.isLocked(pinboardID: first))

        synchronizer.simulateExternalUpdate([second])
        await Task.yield()

        XCTAssertFalse(controller.isLocked(pinboardID: first))
        XCTAssertTrue(controller.isLocked(pinboardID: second))
    }

    func testTemporaryUnlockDoesNotBroadcastUnlockSession() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let synchronizer = StubLockStateSynchronizer()
        let pinboardID = UUID()

        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer
        )
        controller.setLockEnabled(true, pinboardID: pinboardID)
        let publishCountAfterLock = synchronizer.publishCallCount

        _ = await controller.unlock(pinboardID: pinboardID, pinboardName: "Private")

        XCTAssertTrue(controller.canAccess(pinboardID: pinboardID))
        XCTAssertEqual(synchronizer.publishCallCount, publishCountAfterLock)
    }

    private func makeEphemeralDefaults() -> (UserDefaults, String) {
        let suiteName = "PinboardLockControllerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return (.standard, suiteName)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private struct StubPinboardAuthenticator: PinboardAuthenticationProviding {
    let result: Bool

    func authenticate(reason: String) async -> Bool {
        result
    }
}

private final class StubLockStateSynchronizer: PinboardLockStateSynchronizing {
    private var latest: Set<UUID>?
    private var onChange: (@Sendable (Set<UUID>) -> Void)?
    private(set) var publishCallCount = 0

    func publish(lockedPinboardIDs: Set<UUID>) {
        publishCallCount += 1
        latest = lockedPinboardIDs
    }

    func latestLockedPinboardIDs() -> Set<UUID>? {
        latest
    }

    func startObserving(_ onChange: @escaping @Sendable (Set<UUID>) -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func simulateExternalUpdate(_ ids: Set<UUID>) {
        latest = ids
        onChange?(ids)
    }
}
