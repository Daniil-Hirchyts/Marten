import AppKit
import Carbon.HIToolbox
import ClipboardCore
import ClipboardMacServices
import XCTest

@testable import ClipboardMac

@MainActor
final class HotkeyCoordinatorTests: XCTestCase {
    private final class TestPermissionManager: HotkeyPermissionManaging {
        var isAllowed: Bool
        var didRequestAccessibility = false

        init(isAllowed: Bool) {
            self.isAllowed = isAllowed
        }

        func checkAccessibility(prompt: Bool) -> Bool {
            isAllowed
        }

        func requestAccessibility() {
            didRequestAccessibility = true
        }
    }

    private struct TestPasteSettings: PasteSettingsProviding {
        let alwaysPastePlainText: Bool
    }

    func testTriggersOCRCaptureHotkey() throws {
        let defaults = UserDefaults.standard
        let key = HotkeyPreferenceKey.ocrCapture.rawValue
        let previousData = defaults.data(forKey: key)
        defer {
            if let previousData {
                defaults.set(previousData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let stored = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_O),
            modifiers: [.command, .shift]
        )
        defaults.set(try JSONEncoder().encode(stored), forKey: key)

        let persistence = PersistenceController(inMemory: true)
        let clipItemStore = ClipItemStore(persistence: persistence)
        let hotkeyManager = HotkeyManager()
        let permissionManager = TestPermissionManager(isAllowed: true)
        let pasteEngine = TestPasteEngine()
        let didTrigger = expectation(description: "OCR hotkey triggered")

        let coordinator = HotkeyCoordinator(
            hotkeyManager: hotkeyManager,
            permissionManager: permissionManager,
            clipItemStore: clipItemStore,
            pasteEngine: pasteEngine,
            pasteSettings: TestPasteSettings(alwaysPastePlainText: false),
            toggleOverlay: {},
            hideOverlayForPaste: { completion in completion() },
            triggerOCRCapture: {
                didTrigger.fulfill()
            }
        )

        coordinator.start()
        let consumed = hotkeyManager.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_O),
            flags: [.command, .shift]
        )

        XCTAssertTrue(consumed)
        spinRunLoop(for: 0.2)
        wait(for: [didTrigger], timeout: 1.0)
    }

    func testDoesNotRegisterOCRCaptureWhenCleared() throws {
        let defaults = UserDefaults.standard
        let key = HotkeyPreferenceKey.ocrCapture.rawValue
        let previousData = defaults.data(forKey: key)
        defer {
            if let previousData {
                defaults.set(previousData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let cleared = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_O),
            modifiers: []
        )
        defaults.set(try JSONEncoder().encode(cleared), forKey: key)

        let persistence = PersistenceController(inMemory: true)
        let clipItemStore = ClipItemStore(persistence: persistence)
        let hotkeyManager = HotkeyManager()
        let permissionManager = TestPermissionManager(isAllowed: true)

        let coordinator = HotkeyCoordinator(
            hotkeyManager: hotkeyManager,
            permissionManager: permissionManager,
            clipItemStore: clipItemStore,
            pasteEngine: TestPasteEngine(),
            pasteSettings: TestPasteSettings(alwaysPastePlainText: false),
            toggleOverlay: {},
            hideOverlayForPaste: { completion in completion() },
            triggerOCRCapture: {
                XCTFail("OCR hotkey should not trigger when cleared")
            }
        )

        coordinator.start()
        let consumed = hotkeyManager.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_O),
            flags: [.command, .shift]
        )

        XCTAssertFalse(consumed)
    }
}
