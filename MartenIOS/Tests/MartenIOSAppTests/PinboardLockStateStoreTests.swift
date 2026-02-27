@testable import MartenIOSApp
import MartenCore
import XCTest

@MainActor
final class PinboardLockStateStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "PinboardLockStateStoreTests"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testLockStatePersistsAndReloads() {
        let pinboardID = UUID()
        let synchronizer = StubLockStateSynchronizer()

        let firstStore = PinboardLockStateStore(
            userDefaults: userDefaults,
            lockStateSynchronizer: synchronizer
        )
        firstStore.setLock(true, for: pinboardID)
        XCTAssertTrue(firstStore.isLocked(pinboardID))

        let secondStore = PinboardLockStateStore(
            userDefaults: userDefaults,
            lockStateSynchronizer: synchronizer
        )
        XCTAssertTrue(secondStore.isLocked(pinboardID))

        secondStore.setLock(false, for: pinboardID)
        XCTAssertFalse(secondStore.isLocked(pinboardID))
    }

    func testReconcileRemovesStaleIDs() {
        let first = UUID()
        let second = UUID()
        let synchronizer = StubLockStateSynchronizer()

        let store = PinboardLockStateStore(
            userDefaults: userDefaults,
            lockStateSynchronizer: synchronizer
        )
        store.setLock(true, for: first)
        store.setLock(true, for: second)

        store.reconcile(validPinboardIDs: [first])

        XCTAssertTrue(store.isLocked(first))
        XCTAssertFalse(store.isLocked(second))
    }

    func testUnlockSuccessGrantsTemporaryAccessAndExpires() async {
        let pinboardID = UUID()
        let store = PinboardLockStateStore(
            userDefaults: userDefaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: StubLockStateSynchronizer(),
            unlockDurationSeconds: 1
        )
        store.setLock(true, for: pinboardID)

        XCTAssertFalse(store.canAccess(pinboardID))

        let unlocked = await store.unlock(pinboardID: pinboardID, pinboardName: "Private")
        XCTAssertTrue(unlocked)
        XCTAssertTrue(store.canAccess(pinboardID))

        try? await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertFalse(store.canAccess(pinboardID))
    }

    func testUnlockFailureKeepsPinboardLocked() async {
        let pinboardID = UUID()
        let store = PinboardLockStateStore(
            userDefaults: userDefaults,
            authenticator: StubPinboardAuthenticator(result: false),
            lockStateSynchronizer: StubLockStateSynchronizer()
        )
        store.setLock(true, for: pinboardID)

        let unlocked = await store.unlock(pinboardID: pinboardID, pinboardName: "Private")
        XCTAssertFalse(unlocked)
        XCTAssertTrue(store.isLocked(pinboardID))
        XCTAssertFalse(store.canAccess(pinboardID))
    }

    func testExternalSyncUpdateReplacesLocalLockedSet() async {
        let first = UUID()
        let second = UUID()
        let synchronizer = StubLockStateSynchronizer()
        let store = PinboardLockStateStore(
            userDefaults: userDefaults,
            lockStateSynchronizer: synchronizer
        )

        store.setLock(true, for: first)
        XCTAssertTrue(store.isLocked(first))
        XCTAssertFalse(store.isLocked(second))

        synchronizer.simulateExternalUpdate([second])
        await Task.yield()

        XCTAssertFalse(store.isLocked(first))
        XCTAssertTrue(store.isLocked(second))
    }

    func testTemporaryUnlockDoesNotBroadcastUnlockState() async {
        let pinboardID = UUID()
        let synchronizer = StubLockStateSynchronizer()
        let store = PinboardLockStateStore(
            userDefaults: userDefaults,
            authenticator: StubPinboardAuthenticator(result: true),
            lockStateSynchronizer: synchronizer,
            unlockDurationSeconds: 30
        )
        store.setLock(true, for: pinboardID)
        let publishCountAfterLock = synchronizer.publishCallCount

        _ = await store.unlock(pinboardID: pinboardID, pinboardName: "Private")

        XCTAssertTrue(store.canAccess(pinboardID))
        XCTAssertEqual(synchronizer.publishCallCount, publishCountAfterLock)
    }
}

private struct StubPinboardAuthenticator: PinboardAuthenticationProviding {
    let result: Bool

    func authenticate(reason: String) async -> Bool {
        result
    }
}

private final class StubLockStateSynchronizer: PinboardLockStateSynchronizing {
    private var latest: Set<UUID>?
    private var changeHandler: (@Sendable (Set<UUID>) -> Void)?
    private(set) var publishCallCount = 0

    func publish(lockedPinboardIDs: Set<UUID>) {
        publishCallCount += 1
        latest = lockedPinboardIDs
    }

    func latestLockedPinboardIDs() -> Set<UUID>? {
        latest
    }

    func startObserving(_ onChange: @escaping @Sendable (Set<UUID>) -> Void) {
        changeHandler = onChange
    }

    func stopObserving() {
        changeHandler = nil
    }

    func simulateExternalUpdate(_ ids: Set<UUID>) {
        latest = ids
        changeHandler?(ids)
    }
}
