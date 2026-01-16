import Combine

public enum PasteEngineValidationFailure: Sendable, Equatable {
    case accessibilityPermissionDenied
    case eventSourceUnavailable
    case targetActivationTimedOut(targetBundleID: String?)
}

public enum ClipboardEvent: Sendable, Equatable {
    case clipboardWillWrite
    case overlayDidShow
    case pasteEngineValidationFailed(PasteEngineValidationFailure)
    case pasteEngineWillRetryActivation(attempt: Int, targetBundleID: String?)
}

public protocol ClipboardEventBroadcaster: AnyObject {
    var events: AnyPublisher<ClipboardEvent, Never> { get }
    func publish(_ event: ClipboardEvent)
}

public final class ClipboardEventBroadcasterImpl: ClipboardEventBroadcaster {
    public var events: AnyPublisher<ClipboardEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<ClipboardEvent, Never>()

    public init() {}

    public func publish(_ event: ClipboardEvent) {
        subject.send(event)
    }
}
