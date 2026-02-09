import XCTest

class SearchModeTests: MartenMacUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }

    func testSearchInteraction() throws {
        let searchField = app.windows["overlay.window"].searchFields["overlay.searchField"]
        XCTAssertTrue(searchField.exists, "Search field must exist")

        searchField.click()
        searchField.typeText("test search query")

        XCTAssertEqual(
            searchField.value as? String, "test search query",
            "Search field should contain typed text")

        // Clear search
        let clearButton = searchField.buttons["cancel"].firstMatch
        if clearButton.exists {
            clearButton.click()
            XCTAssertEqual(
                searchField.value as? String, "", "Search field should be empty after clearing")
        }
    }
}
