import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

enum WatchClipboardBridge {
    @MainActor
    static func copy(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        #if os(iOS)
        UIPasteboard.general.string = trimmed
        return true
        #else
        return false
        #endif
    }

    @MainActor
    static func playSuccessHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}
