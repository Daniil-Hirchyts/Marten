import ClipboardCore
import ClipboardMacServices
import XCTest

@testable import ClipboardMac

@MainActor
final class OverlayViewModelTests: XCTestCase {
    func testSelectAllInPasteStackSyncsStackEntries() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")
        let itemC = try store.createTextItem(text: "c")

        let engine = TestPasteEngine()
        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.setMode(.pasteStack)
        viewModel.selectAll(in: [itemA, itemB, itemC])
        spinRunLoop(for: 0.1)

        let stackStore = StackSessionStore(persistence: persistence)
        let session = try stackStore.fetchActiveSession()
        XCTAssertNotNil(session)
        guard let session else { return }

        let entries = try stackStore.fetchEntries(sessionID: session.objectID)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map { $0.position }, [0, 1, 2])
        XCTAssertEqual(
            entries.compactMap { $0.clipItem?.objectID.uriRepresentation() },
            [
                itemA.objectID.uriRepresentation(), itemB.objectID.uriRepresentation(),
                itemC.objectID.uriRepresentation(),
            ]
        )
    }

    func testPasteItemShowsAccessibilityAlertWhenPasteEngineDeniesPermission() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try! store.createTextItem(text: "hello")

        let engine = TestPasteEngine()
        engine.pasteItemError = PasteEngineError.accessibilityPermissionDenied

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.paste(item: item, plainText: true)
        spinRunLoop(for: 0.2)

        XCTAssertTrue(viewModel.showAccessibilityAlert)
        XCTAssertFalse(viewModel.isPasting)
        XCTAssertEqual(viewModel.mode, .browse)
        XCTAssertTrue(viewModel.selectedItemIDs.isEmpty)
        XCTAssertEqual(
            engine.actions,
            [.pasteItem(objectID: item.objectID.uriRepresentation(), format: .plainText)]
        )
    }
}
