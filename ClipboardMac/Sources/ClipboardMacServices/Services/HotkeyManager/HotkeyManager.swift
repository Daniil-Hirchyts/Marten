import Carbon.HIToolbox
import Foundation
import OSLog

struct Hotkey {
    let keyCode: UInt32
    let modifiers: UInt32
}

public final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    public init() {}

    public func registerToggleOverlayHotkey(handler: @escaping () -> Void) {
        self.handler = handler
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
        register(hotkey: hotkey, id: 1)
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func register(hotkey: Hotkey, id: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PST1"), id: id)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            Logger.hotkey.error("Failed to register hotkey: \(status)")
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            HotkeyManager.hotKeyHandler,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            Logger.hotkey.error("Failed to install hotkey handler: \(handlerStatus)")
        } else {
            Logger.hotkey.info("Registered global hotkey")
        }
    }

    private func handleHotKeyEvent() {
        DispatchQueue.main.async { [handler] in
            handler?()
        }
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotKeyEvent()
        return noErr
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + UInt32(scalar.value)
        }
        return result
    }
}
