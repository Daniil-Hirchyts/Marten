import XCTest

class KeyboardNavigationTests: ClipboardMacUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }
    
    func testArrowKeyNavigation() throws {
        let overlay = app.windows["overlay.window"]
        
        // Ensure we have focus
        overlay.click()
        
        let collection = overlay.collectionViews["overlay.itemList"]
        let firstItem = collection.cells.element(boundBy: 0)
        let secondItem = collection.cells.element(boundBy: 1)
        
        guard firstItem.waitForExistence(timeout: 2.0) && secondItem.exists else {
            print("Not enough items to test navigation")
            return
        }
        
        // Assuming first item is auto-selected or we select it
        firstItem.click()
        XCTAssertTrue(firstItem.isSelected)
        
        // Press Down Arrow
        overlay.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        
        // Verify second item is selected
        XCTAssertTrue(secondItem.isSelected, "Second item should be selected after pressing Down Arrow")
        
        // Press Up Arrow
        overlay.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        
        // Verify first item is selected again
        XCTAssertTrue(firstItem.isSelected, "First item should be selected after pressing Up Arrow")
    }
}
