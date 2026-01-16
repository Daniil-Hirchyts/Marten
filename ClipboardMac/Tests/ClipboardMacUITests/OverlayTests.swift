import XCTest

class OverlayTests: ClipboardMacUITestCase {
    
    func testOverlayOpenAndClose() throws {
        // Assuming the app starts with the overlay hidden or in a menu bar state
        // and there is a global hotkey or menu item to open it.
        // For UI tests, we often rely on accessibility elements.
        
        // Example: verify menu bar icon exists
        let statusItem = app.statusItems["menubar.statusItem"]
        XCTAssertTrue(statusItem.exists, "Menu bar status item should exist")
        
        // Open overlay via status item if hotkey simulation is hard
        statusItem.click()
        
        // Verify overlay window appears
        let overlayWindow = app.windows["overlay.window"]
        XCTAssertTrue(overlayWindow.waitForExistence(timeout: 2.0), "Overlay window should appear")
        
        // Close overlay (e.g., clicking outside or pressing escape)
        // Since we can't easily click "outside", let's try pressing Esc
        overlayWindow.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        
        XCTAssertFalse(overlayWindow.exists, "Overlay window should disappear after pressing Escape")
    }
    
    func testOverlayInitialState() throws {
        // Open overlay
        app.statusItems["menubar.statusItem"].click()
        
        let overlayWindow = app.windows["overlay.window"]
        XCTAssertTrue(overlayWindow.waitForExistence(timeout: 2.0))
        
        // Verify essential components are present
        XCTAssertTrue(overlayWindow.collectionViews["overlay.itemList"].exists, "Item list should be visible")
        XCTAssertTrue(overlayWindow.searchFields["overlay.searchField"].exists, "Search field should be visible")
    }
}
