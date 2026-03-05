@testable import MartenIOSApp
import XCTest

final class MartenIOSDefaultsTests: XCTestCase {
    private let suiteName = "MartenIOSDefaultsTests"
    private var userDefaults: UserDefaults!

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

    func testRegisterDefaultsSetsExpectedKeys() {
        MartenIOSDefaults.registerDefaults(userDefaults)

        XCTAssertTrue(userDefaults.bool(forKey: MartenIOSDefaults.syncEnabledKey))
        XCTAssertFalse(
            userDefaults.bool(forKey: MartenIOSDefaults.syncAutoEnableMigrationCompletedKey)
        )
        XCTAssertEqual(
            userDefaults.string(forKey: MartenIOSDefaults.appearanceKey),
            MartenIOSAppearance.system.rawValue
        )
        XCTAssertTrue(userDefaults.bool(forKey: MartenIOSDefaults.ignoreConfidentialContentKey))
        XCTAssertTrue(userDefaults.bool(forKey: MartenIOSDefaults.ignoreTransientContentKey))
        XCTAssertTrue(userDefaults.bool(forKey: MartenIOSDefaults.showIntegrationsOnboardingKey))
    }

    func testAppearanceRawValueMappingForAllCases() {
        for appearance in MartenIOSAppearance.allCases {
            let recovered = MartenIOSAppearance(rawValue: appearance.rawValue)
            XCTAssertEqual(recovered, appearance, "Round-trip failed for \(appearance)")
        }
    }

    func testAppearanceSystemPreferredColorSchemeIsNil() {
        XCTAssertNil(MartenIOSAppearance.system.preferredColorScheme)
    }

    func testAppearanceLightAndDarkReturnCorrectScheme() {
        XCTAssertNotNil(MartenIOSAppearance.light.preferredColorScheme)
        XCTAssertNotNil(MartenIOSAppearance.dark.preferredColorScheme)
    }

    func testInvalidRawValueReturnsNil() {
        let invalid = MartenIOSAppearance(rawValue: "neon")
        XCTAssertNil(invalid)
    }
}
