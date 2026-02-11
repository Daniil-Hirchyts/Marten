#if canImport(AppIntents)
import AppIntents
@testable import MartenIOSApp
import XCTest

final class ShortcutsIntentTests: XCTestCase {
    func testAppShortcutsProviderExposesAllPhase3Shortcuts() {
        let shortcuts = MartenAppShortcutsProvider.appShortcuts
        XCTAssertEqual(shortcuts.count, 3)
    }

    func testIntentTitlesAreStable() {
        XCTAssertEqual(String(localized: CreateMartenItemIntent.title), "Create Marten Item")
        XCTAssertEqual(String(localized: SearchMartenIntent.title), "Search Marten")
        XCTAssertEqual(String(localized: GetRecentMartenItemIntent.title), "Get Recent Marten Item")
    }
}
#endif
