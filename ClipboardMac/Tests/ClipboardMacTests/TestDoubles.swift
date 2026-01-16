import AppKit
import Combine
import Foundation

@testable import ClipboardMacServices

final class TestClipboardEventBroadcaster: ClipboardEventBroadcaster {
    var events: AnyPublisher<ClipboardEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<ClipboardEvent, Never>()
    private(set) var published: [ClipboardEvent] = []

    func publish(_ event: ClipboardEvent) {
        published.append(event)
        subject.send(event)
    }
}

final class TestPermissionChecker: AccessibilityPermissionChecking {
    var accessibilityAllowed: Bool

    init(accessibilityAllowed: Bool) {
        self.accessibilityAllowed = accessibilityAllowed
    }

    func checkAccessibility(prompt: Bool) -> Bool {
        accessibilityAllowed
    }
}

final class TestActiveAppTracker: ActiveAppTracking {
    var recordedBundleID: String?

    init(recordedBundleID: String?) {
        self.recordedBundleID = recordedBundleID
    }

    func recordFrontmostApp() {}

    func reactivateRecordedApp() {}
}

final class TestKeystrokeSender: PasteKeystrokeSending {
    private(set) var sentConfigurations: [PasteEngineConfiguration] = []
    var sendError: Error?

    func send(configuration: PasteEngineConfiguration) async throws {
        sentConfigurations.append(configuration)
        if let sendError {
            throw sendError
        }
    }
}

final class TestActivationChecker: TargetActivationChecking {
    var isFrontmostResponses: [Bool]
    var waitResponses: [Bool]

    init(isFrontmostResponses: [Bool] = [], waitResponses: [Bool] = []) {
        self.isFrontmostResponses = isFrontmostResponses
        self.waitResponses = waitResponses
    }

    func isTargetAppFrontmost(targetBundleID: String) async -> Bool {
        if !isFrontmostResponses.isEmpty {
            return isFrontmostResponses.removeFirst()
        }
        return false
    }

    func waitForTargetActivation(targetBundleID: String, timeout: TimeInterval) async -> Bool {
        if !waitResponses.isEmpty {
            return waitResponses.removeFirst()
        }
        return false
    }
}

func spinRunLoop(for interval: TimeInterval) {
    let end = Date().addingTimeInterval(interval)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: end)
    }
}
