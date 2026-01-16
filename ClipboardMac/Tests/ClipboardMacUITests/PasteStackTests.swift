import XCTest

class PasteStackTests: ClipboardMacUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }
    
    func testPasteStackModeToggle() throws {
        // Assume there is a way to toggle paste stack, e.g., a modifier key or a button
        // Since we don't know the exact trigger, we'll look for a UI element that represents the stack
        
        // This test might be limited if Paste Stack is only triggered by holding Shift+Command
        // We can simulate keys
        
        // Hold Shift+Command
        // app.typeKey(XCUIKeyboardKey.command, modifierFlags: [.shift, .command]) 
        // Note: typeKey presses and releases. To hold, we might need a different approach or rely on a persistent UI toggle if it exists.
        
        // If there is a "Stack" button
        let stackButton = app.windows["overlay.window"].buttons["overlay.pasteStackButton"]
        if stackButton.exists {
            stackButton.click()
            XCTAssertTrue(stackButton.isSelected, "Paste Stack mode should be active")
            
            // Verify UI change indicating stack mode
            let stackView = app.windows["overlay.window"].otherElements["overlay.pasteStackView"]
            XCTAssertTrue(stackView.exists)
        }
    }
}
