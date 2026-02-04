import Carbon.HIToolbox
import Foundation

public enum DefaultHotkey {
    public static let showClipboard = HotkeyManager.Hotkey(
        keyCode: UInt16(kVK_ANSI_V),
        modifiers: [.command, .shift]
    )

    public static let ocrCapture = HotkeyManager.Hotkey(
        keyCode: UInt16(kVK_ANSI_O),
        modifiers: [.command, .shift]
    )

    public static let nextPinboard = HotkeyManager.Hotkey(
        keyCode: UInt16(kVK_RightArrow),
        modifiers: [.command]
    )

    public static let previousPinboard = HotkeyManager.Hotkey(
        keyCode: UInt16(kVK_LeftArrow),
        modifiers: [.command]
    )

    public static func quickPaste(_ number: Int) -> HotkeyManager.Hotkey {
        let keyCodes: [UInt16] = [
            UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
            UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
            UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
        ]

        let index = max(1, min(number, 9)) - 1
        return HotkeyManager.Hotkey(
            keyCode: keyCodes[index],
            modifiers: [.command]
        )
    }
}
