import AppKit
import ClipboardCore
import ClipboardMacServices
import Combine
import XCTest

@testable import ClipboardMac

@MainActor
final class ItemOperationsHandlerTests: XCTestCase {
    func testCopyItemWritesTextToPasteboardAndPublishesEvent() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Hello")

        let pasteboard = NSPasteboard.withUniqueName()
        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: pasteboard)

        let broadcaster = TestBroadcaster()
        handler.copyItem(
            item,
            selectedItemIDs: [],
            orderedItems: [item],
            eventBroadcaster: broadcaster
        )

        XCTAssertEqual(broadcaster.published, [.clipboardWillWrite])
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "Hello")
    }

    func testCopySelectedItemsJoinsWithNewlines() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let pasteboard = NSPasteboard.withUniqueName()
        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: pasteboard)
        let broadcaster = TestBroadcaster()

        let selected: Set<NSManagedObjectID> = [itemA.objectID, itemB.objectID]
        handler.copyItem(
            itemB,
            selectedItemIDs: selected,
            orderedItems: [itemA, itemB],
            eventBroadcaster: broadcaster
        )

        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "a\nb")
    }

    func testDeleteItemRemovesFromStore() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "x")

        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: .withUniqueName())
        handler.deleteItem(item, selectedItemIDs: []) {}

        let fetched = try store.fetchRecentItems(limit: 10)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testDeleteSelectedItemsRemovesAll() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        var didClearSelection = false
        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: .withUniqueName())
        handler.deleteItem(
            itemA,
            selectedItemIDs: [itemA.objectID, itemB.objectID]
        ) {
            didClearSelection = true
        }

        XCTAssertTrue(didClearSelection)
        let fetched = try store.fetchRecentItems(limit: 10)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testCommitItemRenameTrimsAndClearsEmptyTitle() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "x")

        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: .withUniqueName())
        handler.commitItemRename(itemID: item.objectID, newTitle: "  ")

        let fetched = try store.fetchRecentItems(limit: 10)
        XCTAssertNil(fetched.first?.customTitle)
    }

    func testTogglePinUpdatesPinnedFlag() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "x")
        XCTAssertFalse(item.isPinned)

        let handler = ItemOperationsHandler(store: store, soundPlayer: SoundEffectPlayer(), pasteboard: .withUniqueName())
        handler.togglePin(item, allowPinning: true)

        XCTAssertTrue(item.isPinned)
    }
}

private final class TestBroadcaster: ClipboardEventBroadcaster {
    private(set) var published: [ClipboardEvent] = []

    var events: AnyPublisher<ClipboardEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    func publish(_ event: ClipboardEvent) {
        published.append(event)
    }
}
