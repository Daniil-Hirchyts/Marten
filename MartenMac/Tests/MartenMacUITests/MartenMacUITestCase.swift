import XCTest

class MartenMacUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        guard ProcessInfo.processInfo.environment["XCODE_VERSION_ACTUAL"] != nil else {
            throw XCTSkip("UI tests require an Xcode runner with a host app")
        }

        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }
}
