import AppKit
import Carbon.HIToolbox
import MartenMacServices
import Foundation

struct HotkeyPreference: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRawValue = UInt(modifiers.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    var isEnabled: Bool {
        modifiersRawValue != 0
    }

    var hotkey: HotkeyManager.Hotkey? {
        guard isEnabled else { return nil }
        return HotkeyManager.Hotkey(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection(
                .deviceIndependentFlagsMask)
        )
    }

    func cleared() -> HotkeyPreference {
        HotkeyPreference(keyCode: keyCode, modifiers: [])
    }
}

enum HotkeyPreferenceKey: Hashable {
    case showMarten
    case ocrCapture
    case quickPaste(Int)

    var rawValue: String {
        switch self {
        case .showMarten:
            return "hotkey.showMarten"
        case .ocrCapture:
            return "hotkey.ocrCapture"
        case .quickPaste(let index):
            return "hotkey.quickPaste\(index)"
        }
    }

    static var allCases: [HotkeyPreferenceKey] {
        [.showMarten, .ocrCapture] + (1...9).map { .quickPaste($0) }
    }
}

final class HotkeyPreferencesStore: ObservableObject {
    @Published var showMarten: HotkeyPreference
    @Published var ocrCapture: HotkeyPreference
    @Published var quickPaste1: HotkeyPreference
    @Published var quickPaste2: HotkeyPreference
    @Published var quickPaste3: HotkeyPreference
    @Published var quickPaste4: HotkeyPreference
    @Published var quickPaste5: HotkeyPreference
    @Published var quickPaste6: HotkeyPreference
    @Published var quickPaste7: HotkeyPreference
    @Published var quickPaste8: HotkeyPreference
    @Published var quickPaste9: HotkeyPreference

    private let userDefaults: UserDefaults

    private static let defaultShowMarten = HotkeyPreference(
        keyCode: UInt16(kVK_ANSI_V),
        modifiers: [.command, .shift]
    )
    private static let defaultOCRCapture = HotkeyPreference(
        keyCode: UInt16(kVK_ANSI_O),
        modifiers: [.command, .shift]
    )

    private static func defaultQuickPaste(_ index: Int) -> HotkeyPreference {
        let keyCodes: [UInt16] = [
            UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
            UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
            UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
        ]
        let idx = max(1, min(index, 9)) - 1
        return HotkeyPreference(keyCode: keyCodes[idx], modifiers: [.command])
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.showMarten = Self.load(
            key: .showMarten,
            userDefaults: userDefaults,
            defaultValue: Self.defaultShowMarten
        )
        self.ocrCapture = Self.load(
            key: .ocrCapture,
            userDefaults: userDefaults,
            defaultValue: Self.defaultOCRCapture
        )
        self.quickPaste1 = Self.load(key: .quickPaste(1), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(1))
        self.quickPaste2 = Self.load(key: .quickPaste(2), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(2))
        self.quickPaste3 = Self.load(key: .quickPaste(3), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(3))
        self.quickPaste4 = Self.load(key: .quickPaste(4), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(4))
        self.quickPaste5 = Self.load(key: .quickPaste(5), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(5))
        self.quickPaste6 = Self.load(key: .quickPaste(6), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(6))
        self.quickPaste7 = Self.load(key: .quickPaste(7), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(7))
        self.quickPaste8 = Self.load(key: .quickPaste(8), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(8))
        self.quickPaste9 = Self.load(key: .quickPaste(9), userDefaults: userDefaults, defaultValue: Self.defaultQuickPaste(9))
    }

    func quickPaste(_ index: Int) -> HotkeyPreference {
        switch index {
        case 1: return quickPaste1
        case 2: return quickPaste2
        case 3: return quickPaste3
        case 4: return quickPaste4
        case 5: return quickPaste5
        case 6: return quickPaste6
        case 7: return quickPaste7
        case 8: return quickPaste8
        case 9: return quickPaste9
        default: return Self.defaultQuickPaste(index)
        }
    }

    func setQuickPaste(_ index: Int, _ value: HotkeyPreference) {
        switch index {
        case 1: quickPaste1 = value
        case 2: quickPaste2 = value
        case 3: quickPaste3 = value
        case 4: quickPaste4 = value
        case 5: quickPaste5 = value
        case 6: quickPaste6 = value
        case 7: quickPaste7 = value
        case 8: quickPaste8 = value
        case 9: quickPaste9 = value
        default: break
        }
    }

    func save() {
        if showMarten == Self.defaultShowMarten {
            userDefaults.removeObject(forKey: HotkeyPreferenceKey.showMarten.rawValue)
        } else {
            Self.save(showMarten, key: .showMarten, userDefaults: userDefaults)
        }

        if ocrCapture == Self.defaultOCRCapture {
            userDefaults.removeObject(forKey: HotkeyPreferenceKey.ocrCapture.rawValue)
        } else {
            Self.save(ocrCapture, key: .ocrCapture, userDefaults: userDefaults)
        }

        for i in 1...9 {
            let current = quickPaste(i)
            let defaultValue = Self.defaultQuickPaste(i)
            if current == defaultValue {
                userDefaults.removeObject(forKey: HotkeyPreferenceKey.quickPaste(i).rawValue)
            } else {
                Self.save(current, key: .quickPaste(i), userDefaults: userDefaults)
            }
        }
    }

    func resetToDefaults() {
        userDefaults.removeObject(forKey: HotkeyPreferenceKey.showMarten.rawValue)
        userDefaults.removeObject(forKey: HotkeyPreferenceKey.ocrCapture.rawValue)
        for i in 1...9 {
            userDefaults.removeObject(forKey: HotkeyPreferenceKey.quickPaste(i).rawValue)
        }
        showMarten = Self.defaultShowMarten
        ocrCapture = Self.defaultOCRCapture
        quickPaste1 = Self.defaultQuickPaste(1)
        quickPaste2 = Self.defaultQuickPaste(2)
        quickPaste3 = Self.defaultQuickPaste(3)
        quickPaste4 = Self.defaultQuickPaste(4)
        quickPaste5 = Self.defaultQuickPaste(5)
        quickPaste6 = Self.defaultQuickPaste(6)
        quickPaste7 = Self.defaultQuickPaste(7)
        quickPaste8 = Self.defaultQuickPaste(8)
        quickPaste9 = Self.defaultQuickPaste(9)
    }

    static func effectiveHotkey(
        for key: HotkeyPreferenceKey, userDefaults: UserDefaults = .standard
    ) -> HotkeyManager.Hotkey? {
        switch key {
        case .showMarten:
            return load(
                key: key,
                userDefaults: userDefaults,
                defaultValue: Self.defaultShowMarten
            ).hotkey
        case .ocrCapture:
            return load(
                key: key,
                userDefaults: userDefaults,
                defaultValue: Self.defaultOCRCapture
            ).hotkey
        case .quickPaste(let index):
            return load(
                key: key,
                userDefaults: userDefaults,
                defaultValue: Self.defaultQuickPaste(index)
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
        guard preference.isEnabled else {
            return "None"
        }
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
