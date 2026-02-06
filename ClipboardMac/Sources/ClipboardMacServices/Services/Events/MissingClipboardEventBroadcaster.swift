import Combine
import OSLog

/// Sentinel broadcaster that traps when used, indicating missing injection
public final class MissingClipboardEventBroadcaster: ClipboardEventBroadcaster {
    public var events: AnyPublisher<ClipboardEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    public init() {}

    public func publish(_ event: ClipboardEvent) {
        Logger.app.fault("ClipboardEventBroadcaster not injected")
    }
}
