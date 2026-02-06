import ClipboardCore
import XCTest

@testable import ClipboardMac

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testSaveNewTextItemPersistsToHistoryAndClipboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let clipItemStore = ClipItemStore(persistence: persistence)
        let pasteEngine = TestPasteEngine()
        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: clipItemStore,
            pasteEngine: pasteEngine
        )
        let coordinator = AppCoordinator(services: services)
        let text = "Manual note"

        await coordinator.saveNewTextItem(text)

        let items = try clipItemStore.fetchRecentItems(limit: 20)
        let saved = try XCTUnwrap(items.first(where: { $0.primaryText == text }))

        XCTAssertTrue(saved.isUserCreated)
        XCTAssertTrue(pasteEngine.actions.contains(.copyPlainText(text: text)))
    }

    func testSaveNewTextItemStillPersistsHistoryWhenClipboardWriteFails() async throws {
        let persistence = PersistenceController(inMemory: true)
        let clipItemStore = ClipItemStore(persistence: persistence)
        let pasteEngine = TestPasteEngine()
        pasteEngine.copyPlainTextError = TestError.failed
        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: clipItemStore,
            pasteEngine: pasteEngine
        )
        let coordinator = AppCoordinator(services: services)
        let text = "History survives clipboard error"

        await coordinator.saveNewTextItem(text)

        let items = try clipItemStore.fetchRecentItems(limit: 20)
        let saved = try XCTUnwrap(items.first(where: { $0.primaryText == text }))

        XCTAssertTrue(saved.isUserCreated)
        XCTAssertTrue(pasteEngine.actions.contains(.copyPlainText(text: text)))
    }
}
