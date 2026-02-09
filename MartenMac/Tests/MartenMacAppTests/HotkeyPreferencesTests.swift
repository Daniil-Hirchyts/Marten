import Carbon.HIToolbox
import MartenMacServices
import XCTest

@testable import MartenMac

final class HotkeyPreferencesTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let suite = "test.hotkeys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = HotkeyPreferencesStore(userDefaults: defaults)
        store.showMarten = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift])
        store.ocrCapture = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_O), modifiers: [.command, .option])
        store.setQuickPaste(
            1,
            HotkeyPreference(
                keyCode: UInt16(kVK_ANSI_P), modifiers: [.command]))
        store.save()

        let store2 = HotkeyPreferencesStore(userDefaults: defaults)
        XCTAssertEqual(store2.showMarten, store.showMarten)
        XCTAssertEqual(store2.ocrCapture, store.ocrCapture)
        XCTAssertEqual(store2.quickPaste(1), store.quickPaste(1))
    }

    func testEffectiveHotkeyUsesDefaultWhenUnset() {
        let suite = "test.hotkeys.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let hotkey = HotkeyPreferencesStore.effectiveHotkey(
            for: .showMarten, userDefaults: defaults)

        XCTAssertNotNil(hotkey)
        guard let hotkey else { return }

        XCTAssertEqual(hotkey.keyCode, UInt16(kVK_ANSI_V))
        XCTAssertTrue(hotkey.modifiers.contains(.command))
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
    }

    func testEffectiveHotkeyUsesDefaultForQuickPaste() {
        let suite = "test.hotkeys.quickpaste.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let hotkey = HotkeyPreferencesStore.effectiveHotkey(
            for: .quickPaste(1), userDefaults: defaults)

        XCTAssertNotNil(hotkey)
        guard let hotkey else { return }

        XCTAssertEqual(hotkey.keyCode, UInt16(kVK_ANSI_1))
        XCTAssertTrue(hotkey.modifiers.contains(.command))
    }

    func testEffectiveHotkeyUsesDefaultForOCRCapture() {
        let suite = "test.hotkeys.ocr.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let hotkey = HotkeyPreferencesStore.effectiveHotkey(
            for: .ocrCapture,
            userDefaults: defaults
        )

        XCTAssertNotNil(hotkey)
        guard let hotkey else { return }

        XCTAssertEqual(hotkey.keyCode, UInt16(kVK_ANSI_O))
        XCTAssertTrue(hotkey.modifiers.contains(.command))
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
    }

    func testResetToDefaultsClearsSavedValues() {
        let suite = "test.hotkeys.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = HotkeyPreferencesStore(userDefaults: defaults)
        store.showMarten = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift])
        store.save()
        XCTAssertNotNil(defaults.data(forKey: HotkeyPreferenceKey.showMarten.rawValue))

        store.resetToDefaults()
        store.save()

        XCTAssertNil(defaults.data(forKey: HotkeyPreferenceKey.showMarten.rawValue))
        XCTAssertNil(defaults.data(forKey: HotkeyPreferenceKey.ocrCapture.rawValue))
        XCTAssertEqual(store.showMarten.keyCode, UInt16(kVK_ANSI_V))
        XCTAssertEqual(store.ocrCapture.keyCode, UInt16(kVK_ANSI_O))
    }

    func testDisplayStringIncludesModifiersAndKey() {
        let pref = HotkeyPreference(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift])
        let text = HotkeyDisplay.string(for: pref)
        XCTAssertTrue(text.contains("⌘"))
        XCTAssertTrue(text.contains("⇧"))
        XCTAssertTrue(text.contains("V"))
    }

    func testKeyNameCoversKnownKeyCodes() {
        let codes: [UInt16] = [
            UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_B), UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_D),
            UInt16(kVK_ANSI_E), UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_G), UInt16(kVK_ANSI_H),
            UInt16(kVK_ANSI_I), UInt16(kVK_ANSI_J), UInt16(kVK_ANSI_K), UInt16(kVK_ANSI_L),
            UInt16(kVK_ANSI_M), UInt16(kVK_ANSI_N), UInt16(kVK_ANSI_O), UInt16(kVK_ANSI_P),
            UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_R), UInt16(kVK_ANSI_S), UInt16(kVK_ANSI_T),
            UInt16(kVK_ANSI_U), UInt16(kVK_ANSI_V), UInt16(kVK_ANSI_W), UInt16(kVK_ANSI_X),
            UInt16(kVK_ANSI_Y), UInt16(kVK_ANSI_Z),
            UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
            UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7),
            UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9),
            UInt16(kVK_Space), UInt16(kVK_Tab), UInt16(kVK_Return), UInt16(kVK_Escape),
            UInt16(kVK_Delete), UInt16(kVK_ForwardDelete),
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow), UInt16(kVK_UpArrow),
            UInt16(kVK_DownArrow),
        ]
        for code in codes {
            XCTAssertFalse(HotkeyDisplay.keyName(for: code).isEmpty)
        }
    }
}
