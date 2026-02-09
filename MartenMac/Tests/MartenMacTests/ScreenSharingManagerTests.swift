import MartenMacServices
import XCTest

@MainActor
final class ScreenSharingManagerTests: XCTestCase {
    private final class TestSettings: ScreenSharingSettingsProviding {
        var value: Bool

        init(_ value: Bool) {
            self.value = value
        }

        func showDuringScreenSharing() -> Bool {
            value
        }

        func setShowDuringScreenSharing(_ value: Bool) {
            self.value = value
        }
    }

    func testShouldShowOverlayWhenNotInScreenSharingMode() {
        let settings = TestSettings(false)
        let manager = ScreenSharingManager(settings: settings)

        manager.deactivate()
        XCTAssertTrue(manager.shouldShowOverlay)
    }

    func testShouldHideOverlayDuringScreenSharingWhenPreferenceDisabled() {
        let settings = TestSettings(false)
        let manager = ScreenSharingManager(settings: settings)

        manager.activate()
        XCTAssertFalse(manager.shouldShowOverlay)
    }

    func testShouldShowOverlayDuringScreenSharingWhenPreferenceEnabled() {
        let settings = TestSettings(true)
        let manager = ScreenSharingManager(settings: settings)

        manager.activate()
        XCTAssertTrue(manager.shouldShowOverlay)
    }

    func testPreferenceSetterUpdatesProvider() {
        let settings = TestSettings(true)
        let manager = ScreenSharingManager(settings: settings)

        manager.showDuringScreenSharingPreference = false
        XCTAssertFalse(settings.value)
        XCTAssertFalse(manager.showDuringScreenSharingPreference)
    }
}
