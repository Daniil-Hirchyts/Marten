import Combine
import OSLog

/// Sentinel broadcaster that traps when used, indicating missing injection
public final class MissingClipboardEventBroadcaster: ClipboardEventBroadcaster {
    public var events: AnyPublisher<ClipboardEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    public init() {}

    public func publish(_ event: ClipboardEvent) {
        #if DEBUG
        assertionFailure("ClipboardEventBroadcaster not injected! Ensure .environment(\\.clipboardEventBroadcaster, ...) is set.")
        #else
        Logger.app.fault("ClipboardEventBroadcaster not injected")
        #endif
    }
}
