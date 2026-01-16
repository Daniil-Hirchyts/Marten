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

    func testSetModeBrowseDeletesStackSession() throws {
        let persistence = PersistenceController(inMemory: true)
        let engine = TestPasteEngine()
        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.setMode(.pasteStack)
        spinRunLoop(for: 0.05)

        let stackStore = StackSessionStore(persistence: persistence)
        XCTAssertNotNil(try stackStore.fetchActiveSession())

        viewModel.setMode(.browse)
        spinRunLoop(for: 0.2)

        XCTAssertNil(try stackStore.fetchActiveSession())
    }

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

    func testSelectItemInPasteStackSyncsStackEntries() throws {
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

        viewModel.setMode(.pasteStack)
        viewModel.selectItem(
            itemA, in: [itemA, itemB, itemC], isShiftPressed: false, isCommandPressed: false)
        viewModel.selectItem(
            itemB, in: [itemA, itemB, itemC], isShiftPressed: false, isCommandPressed: true)
        spinRunLoop(for: 0.2)

        let stackStore = StackSessionStore(persistence: persistence)
        let session = try stackStore.fetchActiveSession()
        XCTAssertNotNil(session)
        guard let session else { return }

        let entries = try stackStore.fetchEntries(sessionID: session.objectID)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.compactMap { $0.clipItem?.primaryText }, ["a", "b"])
    }

    func testClearSelectionInPasteStackClearsStackEntries() throws {
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

        viewModel.setMode(.pasteStack)
        viewModel.selectAll(in: [itemA, itemB])
        spinRunLoop(for: 0.2)

        let stackStore = StackSessionStore(persistence: persistence)
        let session = try stackStore.fetchActiveSession()
        XCTAssertNotNil(session)
        guard let session else { return }

        XCTAssertEqual(try stackStore.fetchEntries(sessionID: session.objectID).count, 2)

        viewModel.clearSelection()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(try stackStore.fetchEntries(sessionID: session.objectID).count, 0)
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

    func testPasteItemCopiesToClipboardWhenPasteToActiveAppDisabled() {
        UserDefaults.standard.set(false, forKey: "pasteToActiveApp")
        defer { UserDefaults.standard.removeObject(forKey: "pasteToActiveApp") }

        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try! store.createTextItem(text: "hello")

        let engine = TestPasteEngine()

        let viewModel = OverlayViewModel(
            persistence: persistence,
            pasteEngine: engine,
            permissionManager: PermissionManager()
        ) { completion in
            completion()
        }

        viewModel.paste(item: item, plainText: true)
        spinRunLoop(for: 0.2)

        XCTAssertFalse(viewModel.showAccessibilityAlert)
        XCTAssertFalse(viewModel.isPasting)
        XCTAssertEqual(
            engine.actions,
            [.copyItem(objectID: item.objectID.uriRepresentation(), format: .plainText)]
        )
    }

    func testPasteStackCopiesToClipboardWhenPasteToActiveAppDisabled() throws {
        UserDefaults.standard.set(false, forKey: "pasteToActiveApp")
        defer { UserDefaults.standard.removeObject(forKey: "pasteToActiveApp") }

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

        viewModel.setMode(.pasteStack)
        viewModel.selectAll(in: [itemA, itemB])
        spinRunLoop(for: 0.1)

        viewModel.pasteStack(plainText: true)
        spinRunLoop(for: 0.2)

        XCTAssertTrue(
            engine.actions.contains { action in
                if case .copyStack(sessionID: _) = action {
                    return true
                }
                return false
            })
    }

}
