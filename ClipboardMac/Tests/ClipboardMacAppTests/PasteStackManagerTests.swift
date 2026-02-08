import ClipboardCore
import XCTest

@testable import ClipboardMac

@MainActor
final class PasteStackManagerTests: XCTestCase {
    private final class SpyOverlayViewModel: OverlayPasting {
        enum Call: Equatable {
            case paste(URL, plainText: Bool)
            case pasteMultiple(itemCount: Int, plainText: Bool)
        }

        var selectedItemIDs: Set<NSManagedObjectID> = []
        private(set) var calls: [Call] = []
        private(set) var lastPastedItems: [ClipItem] = []

        func paste(item: ClipItem, plainText: Bool) {
            calls.append(.paste(item.objectID.uriRepresentation(), plainText: plainText))
        }

        func pasteMultipleItems(_ items: [ClipItem], plainText: Bool) {
            lastPastedItems = items
            calls.append(.pasteMultiple(itemCount: items.count, plainText: plainText))
        }
    }

    func testPasteItemOrSelectionPastesSingleWhenSelectionIsOne() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createTextItem(text: "a")
        let b = try store.createTextItem(text: "b")

        let viewModel = SpyOverlayViewModel()
        viewModel.selectedItemIDs = [a.objectID]

        let manager = PasteStackManager()
        manager.pasteItemOrSelection(
            item: b,
            plainText: false,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: [a, b],
            viewModel: viewModel
        )

        XCTAssertEqual(viewModel.calls, [.paste(b.objectID.uriRepresentation(), plainText: false)])
    }

    func testPasteItemOrSelectionPastesMultipleAsPlainTextWhenMultiSelectionIncludesTappedItem()
        throws
    {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createTextItem(text: "a")
        let b = try store.createTextItem(text: "b")

        let viewModel = SpyOverlayViewModel()
        viewModel.selectedItemIDs = [a.objectID, b.objectID]

        let manager = PasteStackManager()
        manager.pasteItemOrSelection(
            item: a,
            plainText: true,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: [a, b],
            viewModel: viewModel
        )

        XCTAssertEqual(viewModel.calls, [.pasteMultiple(itemCount: 2, plainText: true)])
        XCTAssertEqual(viewModel.lastPastedItems.count, 2)
    }

    func testPasteOutsidePastesMultipleAsPlainTextAfterDelay() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createTextItem(text: "a")
        let b = try store.createTextItem(text: "b")

        let viewModel = SpyOverlayViewModel()
        let manager = PasteStackManager()
        manager.pasteOutside(
            itemIDs: [a.objectID, b.objectID],
            plainText: true,
            orderedItems: [a, b],
            viewModel: viewModel
        )

        spinRunLoop(for: 0.2)
        XCTAssertEqual(viewModel.calls, [.pasteMultiple(itemCount: 2, plainText: true)])
    }

    func testPasteOutsidePastesMultiplePreservedWhenPlainTextIsFalse() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createTextItem(text: "a")
        let b = try store.createTextItem(text: "b")

        let viewModel = SpyOverlayViewModel()
        let manager = PasteStackManager()
        manager.pasteOutside(
            itemIDs: [a.objectID, b.objectID],
            plainText: false,
            orderedItems: [a, b],
            viewModel: viewModel
        )

        spinRunLoop(for: 0.2)
        XCTAssertEqual(viewModel.calls, [.pasteMultiple(itemCount: 2, plainText: false)])
    }

    func testPasteOutsidePastesSingleItemDirectly() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createTextItem(text: "a")

        let viewModel = SpyOverlayViewModel()
        let manager = PasteStackManager()
        manager.pasteOutside(
            itemIDs: [a.objectID],
            plainText: false,
            orderedItems: [a],
            viewModel: viewModel
        )

        spinRunLoop(for: 0.2)
        XCTAssertEqual(viewModel.calls, [.paste(a.objectID.uriRepresentation(), plainText: false)])
    }
}
