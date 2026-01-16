import ClipboardCore
import XCTest

@testable import ClipboardMac

@MainActor
final class PasteStackManagerTests: XCTestCase {
    private final class SpyOverlayViewModel: OverlayPasting {
        enum Call: Equatable {
            case setMode(OverlayMode)
            case restoreSelection(Set<URL>, orderedCount: Int)
            case paste(URL, plainText: Bool)
            case pasteStack(plainText: Bool)
        }

        var mode: OverlayMode = .browse
        var selectedItemIDs: Set<NSManagedObjectID> = []
        private(set) var calls: [Call] = []

        func setMode(_ mode: OverlayMode) {
            self.mode = mode
            calls.append(.setMode(mode))
        }

        func restoreSelection(_ ids: Set<NSManagedObjectID>, in orderedItems: [ClipItem]) {
            selectedItemIDs = ids
            calls.append(
                .restoreSelection(
                    Set(ids.map { $0.uriRepresentation() }), orderedCount: orderedItems.count))
        }

        func paste(item: ClipItem, plainText: Bool) {
            calls.append(.paste(item.objectID.uriRepresentation(), plainText: plainText))
        }

        func pasteStack(plainText: Bool) {
            calls.append(.pasteStack(plainText: plainText))
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

    func testPasteItemOrSelectionPastesStackWhenMultiSelectionIncludesTappedItem() throws {
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

        XCTAssertEqual(
            viewModel.calls,
            [
                .setMode(.pasteStack),
                .restoreSelection(
                    Set([a.objectID.uriRepresentation(), b.objectID.uriRepresentation()]),
                    orderedCount: 2),
                .pasteStack(plainText: true),
            ]
        )
    }

    func testPasteOutsideSwitchesToPasteStackAndPastesAfterDelay() throws {
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
        XCTAssertEqual(
            viewModel.calls,
            [
                .setMode(.pasteStack),
                .restoreSelection(
                    Set([a.objectID.uriRepresentation(), b.objectID.uriRepresentation()]),
                    orderedCount: 2),
                .pasteStack(plainText: true),
            ]
        )
    }
}
