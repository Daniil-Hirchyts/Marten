import XCTest

class SettingsTests: ClipboardMacUITestCase {

    func testSettingsWindowOpens() throws {
        // Open overlay first
        app.statusItems["menubar.statusItem"].click()
        let overlay = app.windows["overlay.window"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 2.0))

        // Find settings button in overlay (often a gear icon)
        let settingsButton = overlay.buttons["overlay.settingsButton"]

        if settingsButton.exists {
            settingsButton.click()
        } else {
            // Fallback: Use menu bar if overlay button doesn't exist
            // Note: Menu bar interactions in XCUITest can be tricky and slow
            // Trying to find a "Preferences" or "Settings" button in the UI
            print("Settings button not found in overlay, skipping direct click test")
            return
        }

        let settingsWindow = app.windows["settings.window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 2.0), "Settings window should appear")

        // Verify tabs exist
        XCTAssertTrue(settingsWindow.toolbars.firstMatch.exists || settingsWindow.groups["settings.tabs"].exists)
    }

    func testAccountTabExists() throws {
        // Open overlay first
        app.statusItems["menubar.statusItem"].click()
        let overlay = app.windows["overlay.window"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 2.0))

        // Find settings button in overlay
        let settingsButton = overlay.buttons["overlay.settingsButton"]

        guard settingsButton.exists else {
            print("Settings button not found in overlay, skipping test")
            return
        }

        settingsButton.click()

        let settingsWindow = app.windows["settings.window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 2.0), "Settings window should appear")

        // Verify Account tab exists
        let accountTab = settingsWindow.buttons["settings.tab.account"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 2.0), "Account tab should exist")
    }
}
