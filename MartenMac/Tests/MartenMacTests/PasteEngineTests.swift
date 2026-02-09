import AppKit
import MartenCore
import XCTest

@testable import MartenMacServices

final class PasteEngineTests: XCTestCase {
    func testPasteItemWritesToPasteboardPublishesEventAndSendsKeystroke() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "hello")

        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PasteEngineTests-\(UUID().uuidString)"))
        let broadcaster = TestMartenEventBroadcaster()
        let permission = TestPermissionChecker(accessibilityAllowed: true)
        let tracker = TestActiveAppTracker(recordedBundleID: "com.test.target")
        let keystrokes = TestKeystrokeSender()
        let activation = TestActivationChecker(waitResponses: [true])

        let config = PasteEngineConfiguration(
            pasteKeystroke: .default,
            targetActivation: .init(timeout: 0, maxAttempts: 1, retryDelay: 0),
            interItemDelay: 0
        )

        let engine = PasteEngine(
            pasteboard: pasteboard,
            activeAppTracker: tracker,
            permissionManager: permission,
            eventBroadcaster: broadcaster,
            configuration: config,
            keystrokeSender: keystrokes,
            activationChecker: activation
        )

        try await engine.pasteItem(item, format: .plainText)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertTrue(broadcaster.published.contains(.clipboardWillWrite))
        XCTAssertEqual(keystrokes.sentConfigurations.count, 1)
    }

    func testPasteItemThrowsMissingPlainTextAndDoesNotSendKeystroke() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .png,
                    uti: "public.png",
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    fileExtension: "png"
                )
            ],
            primaryText: nil,
            itemType: .image
        )
        let item = try store.createItem(payload: payload)

        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PasteEngineTests-\(UUID().uuidString)"))
        let broadcaster = TestMartenEventBroadcaster()
        let permission = TestPermissionChecker(accessibilityAllowed: true)
        let tracker = TestActiveAppTracker(recordedBundleID: "com.test.target")
        let keystrokes = TestKeystrokeSender()
        let activation = TestActivationChecker(waitResponses: [true])

        let engine = PasteEngine(
            pasteboard: pasteboard,
            activeAppTracker: tracker,
            permissionManager: permission,
            eventBroadcaster: broadcaster,
            configuration: .default,
            keystrokeSender: keystrokes,
            activationChecker: activation
        )

        do {
            try await engine.pasteItem(item, format: .plainText)
            XCTFail("Expected PasteEngineError.missingPlainText")
        } catch PasteEngineError.missingPlainText {
            XCTAssertEqual(keystrokes.sentConfigurations.count, 0)
        }
    }

    func testPasteItemRetriesTargetActivationAndPublishesRetryEvent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "hello")

        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PasteEngineTests-\(UUID().uuidString)"))
        let broadcaster = TestMartenEventBroadcaster()
        let permission = TestPermissionChecker(accessibilityAllowed: true)
        let tracker = TestActiveAppTracker(recordedBundleID: "com.test.target")
        let keystrokes = TestKeystrokeSender()
        let activation = TestActivationChecker(waitResponses: [false, true])

        let config = PasteEngineConfiguration(
            pasteKeystroke: .default,
            targetActivation: .init(timeout: 0, maxAttempts: 3, retryDelay: 0),
            interItemDelay: 0
        )

        let engine = PasteEngine(
            pasteboard: pasteboard,
            activeAppTracker: tracker,
            permissionManager: permission,
            eventBroadcaster: broadcaster,
            configuration: config,
            keystrokeSender: keystrokes,
            activationChecker: activation
        )

        try await engine.pasteItem(item, format: .plainText)
        XCTAssertTrue(
            broadcaster.published.contains(
                .pasteEngineWillRetryActivation(attempt: 2, targetBundleID: "com.test.target")
            )
        )
        XCTAssertEqual(keystrokes.sentConfigurations.count, 1)
    }
}
