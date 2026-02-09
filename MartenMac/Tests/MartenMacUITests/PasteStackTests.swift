import XCTest

// Paste stack mode has been removed.
// Multi-selection now pastes as newline-joined plain text in a single action.
// These tests are preserved as a placeholder for future multi-selection paste tests.

class PasteStackTests: MartenMacUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }

    func testOverlayOpens() throws {
        XCTAssertTrue(app.windows["overlay.window"].exists)
    }
}
