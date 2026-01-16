import Carbon.HIToolbox
import ClipboardMacServices
import XCTest

@testable import ClipboardMac

final class HotkeyPreferencesTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let suite = "test.hotkeys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = HotkeyPreferencesStore(userDefaults: defaults)
        store.toggleOverlay = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift])
        store.togglePasteStack = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_P), modifiers: [.command])
        store.save()

        let store2 = HotkeyPreferencesStore(userDefaults: defaults)
        XCTAssertEqual(store2.toggleOverlay, store.toggleOverlay)
        XCTAssertEqual(store2.togglePasteStack, store.togglePasteStack)
    }

    func testEffectiveHotkeyUsesDefaultWhenUnset() {
        let suite = "test.hotkeys.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let hotkey = HotkeyPreferencesStore.effectiveHotkey(
            for: .toggleOverlay, userDefaults: defaults)
        XCTAssertEqual(hotkey.keyCode, UInt16(kVK_ANSI_V))
        XCTAssertTrue(hotkey.modifiers.contains(.command))
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
    }

    func testResetToDefaultsClearsSavedValues() {
        let suite = "test.hotkeys.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = HotkeyPreferencesStore(userDefaults: defaults)
        store.toggleOverlay = HotkeyPreference(
            keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift])
        store.save()
        XCTAssertNotNil(defaults.data(forKey: HotkeyPreferenceKey.toggleOverlay.rawValue))

        store.resetToDefaults()
        store.save()

        XCTAssertNil(defaults.data(forKey: HotkeyPreferenceKey.toggleOverlay.rawValue))
        XCTAssertEqual(store.toggleOverlay.keyCode, UInt16(kVK_ANSI_V))
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
