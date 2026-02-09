import MartenMacServices
import SwiftUI

private struct MartenEventBroadcasterKey: EnvironmentKey {
    static let defaultValue: any MartenEventBroadcaster = MissingMartenEventBroadcaster()
}

extension EnvironmentValues {
    var clipboardEventBroadcaster: any MartenEventBroadcaster {
        get { self[MartenEventBroadcasterKey.self] }
        set { self[MartenEventBroadcasterKey.self] = newValue }
    }
}
