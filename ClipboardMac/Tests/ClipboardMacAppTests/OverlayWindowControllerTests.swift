import AppKit
@testable import ClipboardMac
import SwiftUI
import XCTest

@MainActor
final class OverlayWindowControllerTests: XCTestCase {
    func testToggleShowsAndHidesOverlay() {
        _ = NSApplication.shared
        let controller = OverlayWindowController(rootView: AnyView(Text("Test")))

        controller.toggle(mode: .browse)
        spinRunLoop(for: 0.3)
        XCTAssertTrue(controller.isVisibleForTesting)

        controller.toggle(mode: .browse)
        spinRunLoop(for: 0.3)
        XCTAssertFalse(controller.isVisibleForTesting)
    }

    private func spinRunLoop(for interval: TimeInterval) {
        let end = Date().addingTimeInterval(interval)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: end)
        }
    }
}
