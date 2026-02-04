import ClipboardMacServices
import SwiftUI

private struct ClipboardEventBroadcasterKey: EnvironmentKey {
    static let defaultValue: any ClipboardEventBroadcaster = MissingClipboardEventBroadcaster()
}

extension EnvironmentValues {
    var clipboardEventBroadcaster: any ClipboardEventBroadcaster {
        get { self[ClipboardEventBroadcasterKey.self] }
        set { self[ClipboardEventBroadcasterKey.self] = newValue }
    }
}
