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

    func testExactModifierMatchingWithMultipleModifiers() {
        let manager = HotkeyManager()
        let expectation = expectation(description: "hotkey handler")

        // Register Cmd+Shift+V
        manager.register(
            action: "showClipboard",
            hotkey: .init(keyCode: 9, modifiers: [.command, .shift])
        ) { flags in
            XCTAssertTrue(flags.contains(.command))
            XCTAssertTrue(flags.contains(.shift))
            expectation.fulfill()
        }

        // Should trigger with exact match
        let consumed = manager.handleKeyDownForTesting(keyCode: 9, flags: [.command, .shift])
        XCTAssertTrue(consumed, "Should consume event when modifiers match exactly")
        spinRunLoop(for: 0.2)
        wait(for: [expectation], timeout: 1)
    }

    func testDoesNotTriggerWithExtraModifiers() {
        let manager = HotkeyManager()

        // Register Cmd+Shift+V
        manager.register(
            action: "showClipboard",
            hotkey: .init(keyCode: 9, modifiers: [.command, .shift])
        ) { _ in
            XCTFail("Handler should not be called with extra modifiers")
        }

        // Should NOT trigger with extra modifier (Option)
        let consumed = manager.handleKeyDownForTesting(keyCode: 9, flags: [.command, .shift, .option])
        XCTAssertFalse(consumed, "Should not consume event when extra modifiers are present")
    }

    func testDoesNotTriggerWithFewerModifiers() {
        let manager = HotkeyManager()

        // Register Cmd+Shift+V
        manager.register(
            action: "showClipboard",
            hotkey: .init(keyCode: 9, modifiers: [.command, .shift])
        ) { _ in
            XCTFail("Handler should not be called with fewer modifiers")
        }

        // Should NOT trigger with only Cmd
        let consumed = manager.handleKeyDownForTesting(keyCode: 9, flags: [.command])
        XCTAssertFalse(consumed, "Should not consume event when fewer modifiers are present")
    }
}
