import ClipboardCore
import ClipboardMacServices
import XCTest

@testable import ClipboardMac

@MainActor
final class OverlayViewModelTests: XCTestCase {
    func testRestoreSelectionUpdatesSelectedIDs() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.restoreSelection([itemA.objectID, itemB.objectID], in: [itemA, itemB])
        XCTAssertEqual(viewModel.selectedItemIDs, [itemA.objectID, itemB.objectID])
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

    func testPasteMultipleItemsAsPlainTextJoinsContent() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let engine = TestPasteEngine()
        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.pasteMultipleItemsAsPlainText([itemA, itemB])
        spinRunLoop(for: 0.2)

        XCTAssertFalse(viewModel.isPasting)
        XCTAssertEqual(engine.actions, [.pastePlainText(text: "a\nb")])
    }

    func testPasteMultipleItemsAsPlainTextShowsAccessibilityAlert() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let engine = TestPasteEngine()
        engine.pastePlainTextError = PasteEngineError.accessibilityPermissionDenied

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.pasteMultipleItemsAsPlainText([itemA, itemB])
        spinRunLoop(for: 0.2)

        XCTAssertTrue(viewModel.showAccessibilityAlert)
    }

    func testSelectItemUpdatesSelectedIDs() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.selectItem(itemA, in: [itemA, itemB], isShiftPressed: false, isCommandPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemA.objectID])
    }

    func testClearSelectionRemovesAllSelectedIDs() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.restoreSelection([itemA.objectID, itemB.objectID], in: [itemA, itemB])
        XCTAssertEqual(viewModel.selectedItemIDs.count, 2)

        viewModel.clearSelection()
        XCTAssertTrue(viewModel.selectedItemIDs.isEmpty)
    }

    func testEnsureDefaultSelectionSelectsFirstOrderedItemWhenSelectionIsEmpty() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.ensureDefaultSelection(in: [itemB, itemA])
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID])
    }

    func testEnsureDefaultSelectionPreservesVisibleSelection() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.restoreSelection([itemA.objectID], in: [itemA, itemB])
        viewModel.ensureDefaultSelection(in: [itemB, itemA])
        XCTAssertEqual(viewModel.selectedItemIDs, [itemA.objectID])
    }

    func testEnsureDefaultSelectionReplacesSelectionWhenNoItemsRemainVisible() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.restoreSelection([itemA.objectID], in: [itemA, itemB])
        viewModel.ensureDefaultSelection(in: [itemB])
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID])
    }
}
