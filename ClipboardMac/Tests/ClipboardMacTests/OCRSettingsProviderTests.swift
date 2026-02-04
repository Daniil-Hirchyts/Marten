import ClipboardMacServices
import XCTest

final class OCRSettingsProviderTests: XCTestCase {
    func testDefaultsWhenUnset() {
        let defaults = makeIsolatedUserDefaults()
        let provider = UserDefaultsOCRSettingsProvider(userDefaults: defaults)

        XCTAssertEqual(provider.defaultCaptureMode, .staticSnapshot)
        XCTAssertNil(provider.preferredLanguageCode)
        XCTAssertTrue(provider.showCaptureNotification)
    }

    func testReadsStoredValues() {
        let defaults = makeIsolatedUserDefaults()
        defaults.set(OCRCaptureMode.liveScreen.rawValue, forKey: OCRSettingsKeys.defaultMode)
        defaults.set("uk-UA", forKey: OCRSettingsKeys.preferredLanguage)
        defaults.set(false, forKey: OCRSettingsKeys.showCaptureNotification)

        let provider = UserDefaultsOCRSettingsProvider(userDefaults: defaults)

        XCTAssertEqual(provider.defaultCaptureMode, .liveScreen)
        XCTAssertEqual(provider.preferredLanguageCode, "uk-UA")
        XCTAssertFalse(provider.showCaptureNotification)
    }

    func testAutoLanguageReturnsNil() {
        let defaults = makeIsolatedUserDefaults()
        defaults.set("", forKey: OCRSettingsKeys.preferredLanguage)

        let provider = UserDefaultsOCRSettingsProvider(userDefaults: defaults)

        XCTAssertNil(provider.preferredLanguageCode)
    }

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "OCRSettingsProviderTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
