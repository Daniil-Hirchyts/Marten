import ClipboardMacServices
import XCTest

final class LinkPreviewSettingsProviderTests: XCTestCase {
    func testDefaultsToDisabledWhenUnset() {
        let userDefaults = makeIsolatedUserDefaults()
        let provider = UserDefaultsLinkPreviewSettingsProvider(userDefaults: userDefaults)

        XCTAssertFalse(provider.isLinkPreviewEnabled)
    }

    func testReadsStoredPreference() {
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(true, forKey: "generateLinkPreviews")
        let provider = UserDefaultsLinkPreviewSettingsProvider(userDefaults: userDefaults)

        XCTAssertTrue(provider.isLinkPreviewEnabled)
    }

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "LinkPreviewSettingsProviderTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
