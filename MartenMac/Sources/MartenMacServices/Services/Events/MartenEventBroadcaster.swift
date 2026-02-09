import Combine

public enum PasteEngineValidationFailure: Sendable, Equatable {
    case accessibilityPermissionDenied
    case eventSourceUnavailable
    case targetActivationTimedOut(targetBundleID: String?)
}

public enum MartenEvent: Sendable, Equatable {
    case clipboardWillWrite
    case overlayDidShow
    case pasteEngineValidationFailed(PasteEngineValidationFailure)
    case pasteEngineWillRetryActivation(attempt: Int, targetBundleID: String?)
}

public protocol MartenEventBroadcaster: AnyObject {
    var events: AnyPublisher<MartenEvent, Never> { get }
    func publish(_ event: MartenEvent)
}

public final class MartenEventBroadcasterImpl: MartenEventBroadcaster {
    public var events: AnyPublisher<MartenEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<MartenEvent, Never>()

    public init() {}

    public func publish(_ event: MartenEvent) {
        subject.send(event)
    }
}
