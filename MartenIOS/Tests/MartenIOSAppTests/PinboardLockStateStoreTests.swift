@testable import MartenIOSApp
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

        let firstStore = PinboardLockStateStore(userDefaults: userDefaults)
        firstStore.setLock(true, for: pinboardID)
        XCTAssertTrue(firstStore.isLocked(pinboardID))

        let secondStore = PinboardLockStateStore(userDefaults: userDefaults)
        XCTAssertTrue(secondStore.isLocked(pinboardID))

        secondStore.setLock(false, for: pinboardID)
        XCTAssertFalse(secondStore.isLocked(pinboardID))
    }

    func testReconcileRemovesStaleIDs() {
        let first = UUID()
        let second = UUID()

        let store = PinboardLockStateStore(userDefaults: userDefaults)
        store.setLock(true, for: first)
        store.setLock(true, for: second)

        store.reconcile(validPinboardIDs: [first])

        XCTAssertTrue(store.isLocked(first))
        XCTAssertFalse(store.isLocked(second))
    }
}
