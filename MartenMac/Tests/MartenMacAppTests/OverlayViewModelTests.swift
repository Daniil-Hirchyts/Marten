import MartenCore
import MartenMacServices
import XCTest

@testable import MartenMac

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

    func testPasteMultipleItemsUsesPlainTextForTextItemsByDefault() throws {
        UserDefaults.standard.set(false, forKey: "alwaysPastePlainText")

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

        viewModel.pasteMultipleItems([itemA, itemB], plainText: false)
        spinRunLoop(for: 0.2)

        XCTAssertEqual(engine.actions, [.pastePlainText(text: "a\nb")])
    }

    func testPasteMultipleItemsPreservesPayloadForFilesAndImages() throws {
        UserDefaults.standard.set(false, forKey: "alwaysPastePlainText")

        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let fileItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .fileURL,
                        uti: "public.file-url",
                        text: "/tmp/sample.png",
                        fileExtension: "png"
                    )
                ],
                primaryText: "sample.png",
                itemType: .file
            )
        )
        let imageItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .png,
                        uti: "public.png",
                        data: Data([0x89, 0x50, 0x4E, 0x47]),
                        fileExtension: "png"
                    )
                ],
                primaryText: "screenshot.png",
                itemType: .image
            )
        )

        let engine = TestPasteEngine()
        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.pasteMultipleItems([fileItem, imageItem], plainText: false)
        spinRunLoop(for: 0.45)

        XCTAssertEqual(
            engine.actions,
            [
                .pasteItem(objectID: fileItem.objectID.uriRepresentation(), format: .preserved),
                .pasteItem(objectID: imageItem.objectID.uriRepresentation(), format: .preserved),
            ]
        )
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

    func testEnsureDefaultSelectionLeavesSelectionEmptyWhenSelectionIsEmpty() throws {
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
        XCTAssertTrue(viewModel.selectedItemIDs.isEmpty)
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

    func testEnsureDefaultSelectionPrunesSelectionWhenNoItemsRemainVisible() throws {
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
        XCTAssertTrue(viewModel.selectedItemIDs.isEmpty)
    }

    func testSingleClickOnAlreadySelectedItemKeepsSelection() throws {
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
        viewModel.selectItem(itemA, in: [itemA, itemB], isShiftPressed: false, isCommandPressed: false)

        XCTAssertEqual(viewModel.selectedItemIDs, [itemA.objectID])
    }

    func testShiftClickReplacesSelectionWithContiguousRange() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")
        let itemC = try store.createTextItem(text: "c")
        let itemD = try store.createTextItem(text: "d")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        let orderedItems = [itemA, itemB, itemC, itemD]
        viewModel.selectItem(itemB, in: orderedItems, isShiftPressed: false, isCommandPressed: false)
        viewModel.selectItem(itemD, in: orderedItems, isShiftPressed: true, isCommandPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID, itemC.objectID, itemD.objectID])

        // Shift-click back should replace range from same anchor (itemB) to itemC.
        viewModel.selectItem(itemC, in: orderedItems, isShiftPressed: true, isCommandPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID, itemC.objectID])
    }

    func testKeyboardShiftNavigationUsesDeterministicMouseAnchor() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")
        let itemC = try store.createTextItem(text: "c")
        let itemD = try store.createTextItem(text: "d")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        let orderedItems = [itemA, itemB, itemC, itemD]
        viewModel.selectItem(itemB, in: orderedItems, isShiftPressed: false, isCommandPressed: false)
        viewModel.selectItem(itemD, in: orderedItems, isShiftPressed: true, isCommandPressed: false)

        // Cursor moves from D to C, anchor remains B.
        viewModel.moveSelection(direction: -1, in: orderedItems, isShiftPressed: true)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID, itemC.objectID])

        // Non-shift arrow collapses to a single cursor selection.
        viewModel.moveSelection(direction: -1, in: orderedItems, isShiftPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID])
    }

    func testPruningSelectionRepairsAnchorCursorForNextShiftSelection() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")
        let itemC = try store.createTextItem(text: "c")

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: TestPasteEngine(),
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        let orderedItems = [itemA, itemB, itemC]
        viewModel.selectItem(itemA, in: orderedItems, isShiftPressed: false, isCommandPressed: false)
        viewModel.selectItem(itemC, in: orderedItems, isShiftPressed: true, isCommandPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemA.objectID, itemB.objectID, itemC.objectID])

        // Prune out the old anchor.
        viewModel.ensureDefaultSelection(in: [itemB, itemC])
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID, itemC.objectID])

        // Next shift-click should use repaired endpoints from visible items only.
        viewModel.selectItem(itemB, in: [itemB, itemC], isShiftPressed: true, isCommandPressed: false)
        XCTAssertEqual(viewModel.selectedItemIDs, [itemB.objectID])
    }
}
