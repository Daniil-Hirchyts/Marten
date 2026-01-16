import AppKit
import XCTest

@testable import ClipboardMacServices

final class HotkeyManagerTests: XCTestCase {
    func testHandleKeyDownForTestingInvokesHandlerAndConsumesEvent() {
        let manager = HotkeyManager()
        let expectation = expectation(description: "hotkey handler")

        manager.register(
            action: "paste",
            hotkey: .init(keyCode: 12, modifiers: [.command])
        ) { flags in
            XCTAssertTrue(flags.contains(.command))
            expectation.fulfill()
        }

        let consumed = manager.handleKeyDownForTesting(keyCode: 12, flags: [.command])
        XCTAssertTrue(consumed)
        spinRunLoop(for: 0.2)
        wait(for: [expectation], timeout: 1)
    }

    func testHandleKeyDownForTestingDoesNotConsumeWhenNoMatch() {
        let manager = HotkeyManager()
        manager.register(
            action: "paste",
            hotkey: .init(keyCode: 12, modifiers: [.command])
        ) { _ in
            XCTFail("Handler should not be called")
        }

        let consumed = manager.handleKeyDownForTesting(keyCode: 12, flags: [.shift])
        XCTAssertFalse(consumed)
    }

    func testUnregisterStopsHandlerInvocation() {
        let manager = HotkeyManager()
        manager.register(
            action: "paste",
            hotkey: .init(keyCode: 12, modifiers: [.command])
        ) { _ in
            XCTFail("Handler should not be called")
        }
        manager.unregister(action: "paste")

        let consumed = manager.handleKeyDownForTesting(keyCode: 12, flags: [.command])
        XCTAssertFalse(consumed)
    }
}
