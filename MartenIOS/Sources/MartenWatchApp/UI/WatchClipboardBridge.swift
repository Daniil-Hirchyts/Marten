/// watchOS does not expose a system clipboard API.
/// `copy(text:)` is intentionally a no-op — the "Copied" toast and
/// `markItemUsed` call in the call-site communicate the intent to the user.
#if canImport(WatchKit)
import WatchKit

enum WatchClipboardBridge {
    @discardableResult
    static func copy(text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        // No clipboard access on watchOS; return true so the toast still shows.
        _ = text
        return true
    }

    static func playSuccessHaptic() {
        WKInterfaceDevice.current().play(.success)
    }
}
#else
enum WatchClipboardBridge {
    @discardableResult
    static func copy(text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return true
    }

    static func playSuccessHaptic() {}
}
#endif
