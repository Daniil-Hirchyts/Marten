import ClipboardCore
import ClipboardMacServices
import XCTest

@testable import ClipboardMac

@MainActor
final class PinboardManagerTests: XCTestCase {
    func testCreatePinboardWithPendingItemMovesItemIntoPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createTextItem(text: "move-me")
        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("PinboardTests-\(UUID().uuidString)")))
        )
        let manager = PinboardManager(services: services)

        XCTAssertTrue(manager.createPinboard(name: "Test", colorHex: "#FF0000", pendingItem: item))

        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "Test")
        let pinboard = try persistence.viewContext.fetch(request).first
        XCTAssertNotNil(pinboard)
        let itemURIs = Set(pinboard?.items?.map { $0.objectID.uriRepresentation() } ?? [])
        XCTAssertEqual(itemURIs, [item.objectID.uriRepresentation()])
    }

    func testDeletePinboardReturnsNilWhenDeletingSelectedPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Delete", colorHex: "#00FF00")

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("PinboardTests-\(UUID().uuidString)")))
        )
        let manager = PinboardManager(services: services)
        let updated = manager.deletePinboard(pinboard, selectedPinboardID: pinboard.id)
        XCTAssertNil(updated)

        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", pinboard.id as CVarArg)
        let stillThere = try persistence.viewContext.fetch(request)
        XCTAssertTrue(stillThere.isEmpty)
    }

    func testDeleteSystemClipboardPinboardDoesNothing() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(text: "seed")

        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemClipboard == YES")
        let system = try persistence.viewContext.fetch(request).first
        XCTAssertNotNil(system)
        guard let system else { return }

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("PinboardTests-\(UUID().uuidString)")))
        )
        let manager = PinboardManager(services: services)
        let selection = UUID()
        let updated = manager.deletePinboard(system, selectedPinboardID: selection)
        XCTAssertEqual(updated, selection)

        let remaining = try persistence.viewContext.fetch(request)
        XCTAssertEqual(remaining.count, 1)
    }

    func testOptimisticReorderPinboardsUpdatesSortOrderInMemory() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let a = try store.createPinboard(name: "A", colorHex: "#111111")
        let b = try store.createPinboard(name: "B", colorHex: "#222222")
        let c = try store.createPinboard(name: "C", colorHex: "#333333")

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("PinboardTests-\(UUID().uuidString)")))
        )
        let manager = PinboardManager(services: services)
        manager.optimisticReorderPinboards(
            dragged: c,
            target: a,
            insertBefore: true,
            visiblePinboards: [a, b, c]
        )

        XCTAssertEqual(a.sortOrder, 1)
        XCTAssertEqual(b.sortOrder, 2)
        XCTAssertEqual(c.sortOrder, 0)
    }
}
