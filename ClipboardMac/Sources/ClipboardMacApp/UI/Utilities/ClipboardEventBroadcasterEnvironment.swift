import ClipboardMacServices
import SwiftUI

private struct ClipboardEventBroadcasterKey: EnvironmentKey {
    static let defaultValue: any ClipboardEventBroadcaster = ClipboardEventBroadcasterImpl()
}

extension EnvironmentValues {
    var clipboardEventBroadcaster: any ClipboardEventBroadcaster {
        get { self[ClipboardEventBroadcasterKey.self] }
        set { self[ClipboardEventBroadcasterKey.self] = newValue }
    }
}
