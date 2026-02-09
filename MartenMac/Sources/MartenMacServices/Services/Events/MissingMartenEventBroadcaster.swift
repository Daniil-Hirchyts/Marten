import Combine
import OSLog

/// Sentinel broadcaster that traps when used, indicating missing injection
public final class MissingMartenEventBroadcaster: MartenEventBroadcaster {
    public var events: AnyPublisher<MartenEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    public init() {}

    public func publish(_ event: MartenEvent) {
        Logger.app.fault("MartenEventBroadcaster not injected")
    }
}
