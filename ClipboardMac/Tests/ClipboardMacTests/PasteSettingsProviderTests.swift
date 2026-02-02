import ClipboardMacServices
import XCTest

final class PasteSettingsProviderTests: XCTestCase {
    func testDefaultsToDisabledWhenUnset() {
        let userDefaults = makeIsolatedUserDefaults()
        let provider = UserDefaultsPasteSettingsProvider(userDefaults: userDefaults)

        XCTAssertFalse(provider.alwaysPastePlainText)
    }

    func testReadsStoredPreference() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(true, forKey: "alwaysPastePlainText")
        let provider = UserDefaultsPasteSettingsProvider(userDefaults: userDefaults)

        XCTAssertTrue(provider.alwaysPastePlainText)
    }

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "PasteSettingsProviderTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
