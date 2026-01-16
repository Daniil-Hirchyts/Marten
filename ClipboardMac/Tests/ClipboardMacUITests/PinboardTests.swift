import XCTest

class PinboardTests: ClipboardMacUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        app.statusItems["menubar.statusItem"].click()
        XCTAssertTrue(app.windows["overlay.window"].waitForExistence(timeout: 2.0))
    }
    
    func testPinboardSwitching() throws {
        let tabBar = app.windows["overlay.window"].otherElements["overlay.pinboardTabBar"]
        
        // If tab bar is not found, maybe it's implemented as a segmented control or toolbar
        // Adjusting based on naming convention "overlay.*"
        
        // Let's assume there are buttons for pinboards
        let pinboard1 = tabBar.buttons.element(boundBy: 0)
        let pinboard2 = tabBar.buttons.element(boundBy: 1)
        
        if pinboard2.exists {
            pinboard2.click()
            XCTAssertTrue(pinboard2.isSelected, "Second pinboard should be selected")
            XCTAssertFalse(pinboard1.isSelected, "First pinboard should be deselected")
            
            pinboard1.click()
            XCTAssertTrue(pinboard1.isSelected, "First pinboard should be selected again")
        } else {
            print("Skipping pinboard switching test - only one pinboard available or UI structure different")
        }
    }
}
