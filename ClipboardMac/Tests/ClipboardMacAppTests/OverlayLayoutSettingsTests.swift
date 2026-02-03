import Foundation
import XCTest

@testable import ClipboardMac

final class OverlayLayoutSettingsTests: XCTestCase {
    func testDefaultEdgeIsBottomWhenUnset() {
        let defaults = makeIsolatedDefaults()
        let settings = OverlayLayoutSettings(userDefaults: defaults)

        XCTAssertEqual(settings.overlayScreenEdge, .bottom)
    }

    func testInvalidStoredEdgeFallsBackToBottom() {
        let defaults = makeIsolatedDefaults()
        defaults.set("invalid-edge", forKey: OverlayLayoutSettings.Keys.overlayScreenEdge)
        let settings = OverlayLayoutSettings(userDefaults: defaults)

        XCTAssertEqual(settings.overlayScreenEdge, .bottom)
    }

    func testHorizontalAndVerticalSizesPersistIndependently() {
        let defaults = makeIsolatedDefaults()
        let settings = OverlayLayoutSettings(userDefaults: defaults)

        settings.setPersistedSize(300, for: .horizontal)
        settings.setPersistedSize(480, for: .vertical)

        XCTAssertEqual(settings.persistedSize(for: .horizontal), 300, accuracy: 0.001)
        XCTAssertEqual(settings.persistedSize(for: .vertical), 480, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: OverlayLayoutSettings.Keys.overlayHeight), 300, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: OverlayLayoutSettings.Keys.overlayWidth), 480, accuracy: 0.001)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "OverlayLayoutSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Failed to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
