import XCTest

class ItemCardTests: ClipboardMacUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Open overlay before each test
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }
    
    func testItemSelection() throws {
        let collection = app.windows["overlay.window"].collectionViews["overlay.itemList"]
        XCTAssertTrue(collection.exists)
        
        // Wait for items to load
        let firstItem = collection.cells.firstMatch
        XCTAssertTrue(firstItem.waitForExistence(timeout: 2.0), "Should have at least one item in history")
        
        // Select the first item
        firstItem.click()
        
        // Verify selection state (assuming selected items have a specific indicator or property, 
        // or we just check if it didn't crash/perform action)
        // In a real test, we might check if the preview updated or if the item is highlighted.
        XCTAssertTrue(firstItem.isSelected, "Item should be selected after clicking")
    }
    
    func testItemPreview() throws {
        let collection = app.windows["overlay.window"].collectionViews["overlay.itemList"]
        let firstItem = collection.cells.firstMatch
        XCTAssertTrue(firstItem.waitForExistence(timeout: 2.0))
        
        // Select to show preview
        firstItem.click()
        
        // Verify preview area
        let preview = app.windows["overlay.window"].otherElements["overlay.previewArea"]
        // If preview area might not be marked separately, we check if the detailed view exists
        XCTAssertTrue(preview.exists || app.windows["overlay.window"].images["overlay.previewImage"].exists || app.windows["overlay.window"].staticTexts["overlay.previewText"].exists)
    }
}
