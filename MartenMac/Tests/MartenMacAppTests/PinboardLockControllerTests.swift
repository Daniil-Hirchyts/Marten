import Foundation
import XCTest

@testable import MartenMac

@MainActor
final class PinboardLockControllerTests: XCTestCase {
    func testSetLockEnabledPersistsAndRemovesLockState() async {
        let (defaults, suiteName) = makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true)
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

        defaults.set(1, forKey: PinboardSecuritySettings.unlockDurationSecondsKey)

        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true)
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

        let staleID = UUID()
        let validID = UUID()
        let controller = PinboardLockController(
            userDefaults: defaults,
            authenticator: StubPinboardAuthenticator(result: true)
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
