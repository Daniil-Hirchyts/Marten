import Foundation
@testable import MartenIOSApp

@MainActor
final class MockVoiceRecognitionClient: VoiceRecognitionClient {
    var authorizationGranted = true
    var didStart = false
    var didStop = false

    private var onText: (@MainActor (String, Bool) -> Void)?
    private var onError: (@MainActor (String) -> Void)?

    func requestAuthorization() async -> Bool {
        authorizationGranted
    }

    func startTranscribing(
        onText: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) throws {
        didStart = true
        didStop = false
        self.onText = onText
        self.onError = onError
    }

    func stopTranscribing() {
        didStop = true
    }

    func emit(text: String, isFinal: Bool) {
        onText?(text, isFinal)
    }

    func emitError(_ message: String) {
        onError?(message)
    }
}

final class MockUserActivityDonor: UserActivityDonating {
    private(set) var donatedActivities: [NSUserActivity] = []

    func donate(_ activity: NSUserActivity) {
        donatedActivities.append(activity)
    }
}

// MARK: - MockClipItemQuerying

actor MockClipItemQuerying: ClipItemQuerying {
    private let handler: @Sendable (ClipItemSearchRequest) async throws -> [ClipItem]
    private(set) var capturedRequests: [ClipItemSearchRequest] = []

    init(handler: @escaping @Sendable (ClipItemSearchRequest) async throws -> [ClipItem] = { _ in [] }) {
        self.handler = handler
    }

    func search(request: ClipItemSearchRequest) async throws -> [ClipItem] {
        capturedRequests.append(request)
        return try await handler(request)
    }
}

// MARK: - StubClipItemStore

import CoreData
import MartenCore

/// A thin wrapper that creates a real ClipItemStore backed by an in-memory Core Data stack.
/// Useful for command-service tests that need a real store but isolated persistence.
struct StubStoreFixture {
    let persistence: PersistenceController
    let store: ClipItemStore

    init() {
        persistence = PersistenceController(inMemory: true)
        store = ClipItemStore(persistence: persistence)
    }
}
