import Foundation
@testable import MartenIOSApp
import XCTest

@MainActor
final class IntegrationsStatusModelTests: XCTestCase {
    private let appGroupIdentifier = "group.com.hirchyts.marten.tests.integrations"

    override func tearDown() {
        UserDefaults(suiteName: appGroupIdentifier)?.removePersistentDomain(forName: appGroupIdentifier)
        super.tearDown()
    }

    func testRefreshReadsHeartbeatKeysFromAppGroupDefaults() {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let keyboardTimestamp = Date().addingTimeInterval(-60).timeIntervalSince1970
        let shareTimestamp = Date().addingTimeInterval(-120).timeIntervalSince1970

        defaults?.set(keyboardTimestamp, forKey: MartenIOSDefaults.keyboardLastSeenAtKey)
        defaults?.set(shareTimestamp, forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey)

        let model = IntegrationsStatusModel(appGroupIdentifier: appGroupIdentifier)
        model.refresh()

        XCTAssertNotNil(model.keyboardLastSeenAt)
        XCTAssertNotNil(model.shareExtensionLastSuccessAt)
        XCTAssertTrue(model.keyboardLikelyEnabled)
        XCTAssertTrue(model.shareExtensionRecentlyUsed)
    }

    func testStatusFlagsTurnFalseForStaleHeartbeats() {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let staleTimestamp = Date().addingTimeInterval(-60 * 60 * 24 * 90).timeIntervalSince1970

        defaults?.set(staleTimestamp, forKey: MartenIOSDefaults.keyboardLastSeenAtKey)
        defaults?.set(staleTimestamp, forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey)

        let model = IntegrationsStatusModel(appGroupIdentifier: appGroupIdentifier)
        model.refresh()

        XCTAssertFalse(model.keyboardLikelyEnabled)
        XCTAssertFalse(model.shareExtensionRecentlyUsed)
    }
}
