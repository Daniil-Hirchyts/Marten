import Foundation
import XCTest

@testable import MartenMacServices

final class PasteboardMonitorTests: XCTestCase {
    func testBackgroundCallsRemainSafeAndSynchronous() {
        let monitor = PasteboardMonitor()
        let completed = expectation(description: "background api calls completed")

        DispatchQueue.global().async {
            let token = monitor.suppressNextChange()
            monitor.cancelSuppression(token: token)
            monitor.pause()
            monitor.resume()
            monitor.isEnabled = false
            monitor.isEnabled = true
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1.0)
        XCTAssertTrue(monitor.isEnabled)
        XCTAssertFalse(monitor.isPaused)
    }

    func testPauseForDurationAutoResumes() {
        let monitor = PasteboardMonitor()
        let resumed = expectation(description: "monitor resumed")

        monitor.pauseForDuration(0.05)
        XCTAssertTrue(monitor.isPaused)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertFalse(monitor.isPaused)
            XCTAssertTrue(monitor.isEnabled)
            resumed.fulfill()
        }

        wait(for: [resumed], timeout: 1.0)
    }
}
