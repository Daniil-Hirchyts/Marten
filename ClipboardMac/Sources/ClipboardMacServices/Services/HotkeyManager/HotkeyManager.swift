import AppKit
import Foundation
import OSLog

/// Manages global keyboard hotkeys using a CGEvent tap.
///
/// ## Security Implications
///
/// This manager uses `CGEvent.tapCreate` with `.headInsertEventTap` placement, which means:
/// - **Event Priority**: Hotkey events are intercepted *before* other applications receive them.
///   This is intentional to ensure global hotkeys work reliably regardless of the focused app.
///
///   `.headInsertEventTap` is used (instead of `.tailAppendEventTap`) so the app can detect and
///   optionally consume a registered hotkey before another app processes the same keystroke.
///   This reduces flakiness for global shortcuts, but it also means a matching hotkey can prevent
///   other applications from seeing that exact key combination.
/// - **Accessibility Permission Required**: Creating an event tap requires the user to grant
///   Accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility.
///   Without this permission, `tapCreate` returns `nil`.
/// - **System Trust**: The app is trusted to not maliciously intercept or suppress keystrokes.
///   Only registered hotkeys are consumed; all other events pass through unchanged.
/// - **Potential Conflicts**: Other apps may register overlapping global shortcuts or install
///   competing event taps. Ordering between multiple taps is not under this app’s control, and
///   consuming an event here can cause another app’s shortcut to stop working (and vice versa).
///
/// ## Memory Management
///
/// The event tap callback uses `Unmanaged` to pass `self` as a C pointer (`userInfo`):
/// - `Unmanaged.passUnretained(self).toOpaque()` - Converts `self` to a raw pointer without
///   incrementing the reference count. The caller (this class) must ensure `self` outlives the tap.
/// - `Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()` - Converts the raw
///   pointer back to a HotkeyManager reference without affecting the reference count.
///
///   `fromOpaque(_:)` performs no validation; it assumes the pointer was originally produced by
///   `passUnretained` / `passRetained` for the same type. Using `takeUnretainedValue()` here is
///   required because this code does not transfer ownership to the callback; using
///   `takeRetainedValue()` would incorrectly balance retains/releases and can crash.
///
/// This is safe because:
/// 1. The event tap is created in `start()` and stored in `eventTap`
/// 2. The tap is disabled and cleaned up in `stop()` before the manager is deallocated
/// 3. The manager instance must outlive any registered hotkeys
///
/// ## Error Recovery
///
/// The event tap can be disabled by the system if:
/// - The process times out (takes too long to respond to events)
/// - The user revokes Accessibility permissions
///
/// When this occurs, the callback receives `.tapDisabledByTimeout` or `.tapDisabledByUserInput`.
/// The manager automatically attempts to re-enable the tap in these cases.
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
    private var hasLoggedTapCreateFailure = false

    public init() {}

    public func register(
        action: String, hotkey: Hotkey, handler: @escaping (NSEvent.ModifierFlags) -> Void
    ) {
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

    /// Starts the global hotkey event tap.
    ///
    /// This method creates a CGEvent tap to intercept keyboard events system-wide.
    /// Requires Accessibility permissions to be granted.
    ///
    /// - Note: If the tap fails to create (usually due to missing permissions),
    ///   an error is logged but no exception is thrown.
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // Create the event tap with the following configuration:
        // - .cgSessionEventTap: Tap at the session level (current user session)
        // - .headInsertEventTap: Insert at the front of the event chain so our hotkeys
        //   have priority over other applications. This ensures global hotkeys work
        //   even when other apps might want to capture the same key combination.
        // - .defaultTap: Active tap that can consume events (vs .listenOnly)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                // The callback uses Unmanaged to bridge between C and Swift memory models.
                // See class documentation for detailed memory management explanation.
                callback: { proxy, type, event, refcon in
                    // SAFETY: refcon is guaranteed non-nil as we pass `self` in userInfo below.
                    // We use takeUnretainedValue() because we manage the lifetime ourselves -
                    // the tap is always disabled in stop() before the manager is deallocated.
                    // MEMORY: refcon is an untyped pointer. fromOpaque() assumes it was created via
                    // Unmanaged.passUnretained(self).toOpaque() for the same type.
                    let manager = Unmanaged<HotkeyManager>
                        .fromOpaque(refcon!)
                        .takeUnretainedValue()
                    return manager.handleEvent(proxy: proxy, type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            // Tap creation fails when:
            // 1. The app doesn't have Accessibility permissions
            // 2. The system is under heavy load
            // 3. Too many event taps are already registered
            if !hasLoggedTapCreateFailure {
                Logger.hotkey.error("Failed to create event tap - check Accessibility permissions")
                hasLoggedTapCreateFailure = true
            }
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Logger.hotkey.info("Hotkey event tap started")
        hasLoggedTapCreateFailure = false
        return true
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

    @discardableResult
    public func handleKeyDownForTesting(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        for (action, hotkey) in hotkeys where hotkey.keyCode == keyCode {
            if normalizedFlags.contains(hotkey.modifiers) {
                DispatchQueue.main.async {
                    self.handlers[action]?(normalizedFlags)
                }
                return true
            }
        }
        return false
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events - attempt automatic recovery
        // The system can disable the tap if:
        // 1. .tapDisabledByTimeout - Event processing took too long
        // 2. .tapDisabledByUserInput - User revoked accessibility or system override
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Logger.hotkey.warning(
                "Event tap was disabled by system (type: \(type.rawValue)), attempting to re-enable"
            )
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                Logger.hotkey.info("Event tap re-enabled successfully")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)

        if handleKeyDownForTesting(keyCode: keyCode, flags: flags) {
            return nil
        }

        // Pass through events that don't match any registered hotkey
        return Unmanaged.passUnretained(event)
    }
}
