import AppKit
import Foundation
import OSLog

public final class HotkeyManager {
    public struct Hotkey {
        public let keyCode: UInt16
        public let modifiers: NSEvent.ModifierFlags

        public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeys: [String: Hotkey] = [:]
    private var handlers: [String: (NSEvent.ModifierFlags) -> Void] = [:]

    public init() {}

    public func register(action: String, hotkey: Hotkey, handler: @escaping (NSEvent.ModifierFlags) -> Void) {
        hotkeys[action] = hotkey
        handlers[action] = handler
    }

    public func unregister(action: String) {
        hotkeys.removeValue(forKey: action)
        handlers.removeValue(forKey: action)
    }

    public func unregisterAll() {
        hotkeys.removeAll()
        handlers.removeAll()
    }

    public func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(refcon!)
                    .takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.hotkey.error("Failed to create event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Logger.hotkey.info("Hotkey event tap started")
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)

        for (action, hotkey) in hotkeys where hotkey.keyCode == keyCode {
            if flags.contains(hotkey.modifiers) {
                DispatchQueue.main.async {
                    self.handlers[action]?(flags)
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
