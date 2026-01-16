import AppKit
import Carbon.HIToolbox
import ClipboardMacServices
import Foundation

struct HotkeyPreference: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRawValue = UInt(modifiers.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    var hotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection(
                .deviceIndependentFlagsMask)
        )
    }
}

enum HotkeyPreferenceKey: String, CaseIterable {
    case toggleOverlay = "hotkey.toggleOverlay"
    case togglePasteStack = "hotkey.togglePasteStack"
}

final class HotkeyPreferencesStore: ObservableObject {
    @Published var toggleOverlay: HotkeyPreference
    @Published var togglePasteStack: HotkeyPreference

    private let userDefaults: UserDefaults

    private static let defaultToggleOverlay = HotkeyPreference(
        keyCode: UInt16(kVK_ANSI_V),
        modifiers: [.command, .shift]
    )
    private static let defaultTogglePasteStack = HotkeyPreference(
        keyCode: UInt16(kVK_ANSI_C),
        modifiers: [.command, .shift]
    )

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.toggleOverlay = Self.load(
            key: .toggleOverlay,
            userDefaults: userDefaults,
            defaultValue: Self.defaultToggleOverlay
        )
        self.togglePasteStack = Self.load(
            key: .togglePasteStack,
            userDefaults: userDefaults,
            defaultValue: Self.defaultTogglePasteStack
        )
    }

    func save() {
        if toggleOverlay == Self.defaultToggleOverlay {
            userDefaults.removeObject(forKey: HotkeyPreferenceKey.toggleOverlay.rawValue)
        } else {
            Self.save(toggleOverlay, key: .toggleOverlay, userDefaults: userDefaults)
        }

        if togglePasteStack == Self.defaultTogglePasteStack {
            userDefaults.removeObject(forKey: HotkeyPreferenceKey.togglePasteStack.rawValue)
        } else {
            Self.save(togglePasteStack, key: .togglePasteStack, userDefaults: userDefaults)
        }
    }

    func resetToDefaults() {
        userDefaults.removeObject(forKey: HotkeyPreferenceKey.toggleOverlay.rawValue)
        userDefaults.removeObject(forKey: HotkeyPreferenceKey.togglePasteStack.rawValue)
        toggleOverlay = Self.defaultToggleOverlay
        togglePasteStack = Self.defaultTogglePasteStack
    }

    static func effectiveHotkey(
        for key: HotkeyPreferenceKey, userDefaults: UserDefaults = .standard
    ) -> HotkeyManager.Hotkey {
        switch key {
        case .toggleOverlay:
            return load(
                key: key,
                userDefaults: userDefaults,
                defaultValue: Self.defaultToggleOverlay
            ).hotkey
        case .togglePasteStack:
            return load(
                key: key,
                userDefaults: userDefaults,
                defaultValue: Self.defaultTogglePasteStack
            ).hotkey
        }
    }

    private static func load(
        key: HotkeyPreferenceKey, userDefaults: UserDefaults, defaultValue: HotkeyPreference
    ) -> HotkeyPreference {
        guard let data = userDefaults.data(forKey: key.rawValue) else {
            return defaultValue
        }
        return (try? JSONDecoder().decode(HotkeyPreference.self, from: data)) ?? defaultValue
    }

    private static func save(
        _ value: HotkeyPreference, key: HotkeyPreferenceKey, userDefaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        userDefaults.set(data, forKey: key.rawValue)
    }
}

enum HotkeyDisplay {
    static func string(for preference: HotkeyPreference) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: preference.modifiersRawValue).intersection(
            .deviceIndependentFlagsMask)
        let key = keyName(for: preference.keyCode)
        return "\(modifierSymbols(flags))\(key)"
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case UInt16(kVK_ANSI_A): return "A"
        case UInt16(kVK_ANSI_B): return "B"
        case UInt16(kVK_ANSI_C): return "C"
        case UInt16(kVK_ANSI_D): return "D"
        case UInt16(kVK_ANSI_E): return "E"
        case UInt16(kVK_ANSI_F): return "F"
        case UInt16(kVK_ANSI_G): return "G"
        case UInt16(kVK_ANSI_H): return "H"
        case UInt16(kVK_ANSI_I): return "I"
        case UInt16(kVK_ANSI_J): return "J"
        case UInt16(kVK_ANSI_K): return "K"
        case UInt16(kVK_ANSI_L): return "L"
        case UInt16(kVK_ANSI_M): return "M"
        case UInt16(kVK_ANSI_N): return "N"
        case UInt16(kVK_ANSI_O): return "O"
        case UInt16(kVK_ANSI_P): return "P"
        case UInt16(kVK_ANSI_Q): return "Q"
        case UInt16(kVK_ANSI_R): return "R"
        case UInt16(kVK_ANSI_S): return "S"
        case UInt16(kVK_ANSI_T): return "T"
        case UInt16(kVK_ANSI_U): return "U"
        case UInt16(kVK_ANSI_V): return "V"
        case UInt16(kVK_ANSI_W): return "W"
        case UInt16(kVK_ANSI_X): return "X"
        case UInt16(kVK_ANSI_Y): return "Y"
        case UInt16(kVK_ANSI_Z): return "Z"
        case UInt16(kVK_ANSI_0): return "0"
        case UInt16(kVK_ANSI_1): return "1"
        case UInt16(kVK_ANSI_2): return "2"
        case UInt16(kVK_ANSI_3): return "3"
        case UInt16(kVK_ANSI_4): return "4"
        case UInt16(kVK_ANSI_5): return "5"
        case UInt16(kVK_ANSI_6): return "6"
        case UInt16(kVK_ANSI_7): return "7"
        case UInt16(kVK_ANSI_8): return "8"
        case UInt16(kVK_ANSI_9): return "9"
        case UInt16(kVK_Space): return "Space"
        case UInt16(kVK_Tab): return "Tab"
        case UInt16(kVK_Return): return "Return"
        case UInt16(kVK_Escape): return "Esc"
        case UInt16(kVK_Delete): return "Delete"
        case UInt16(kVK_ForwardDelete): return "Fn+Delete"
        case UInt16(kVK_LeftArrow): return "←"
        case UInt16(kVK_RightArrow): return "→"
        case UInt16(kVK_UpArrow): return "↑"
        case UInt16(kVK_DownArrow): return "↓"
        default:
            return "Key(\(keyCode))"
        }
    }
}
