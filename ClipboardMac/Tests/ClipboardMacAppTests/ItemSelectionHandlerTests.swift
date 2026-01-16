import ClipboardCore
import CoreData
import XCTest

@testable import ClipboardMac

final class ItemSelectionHandlerTests: XCTestCase {
    func testSingleClickSelectsOnlyTappedItem() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 5, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [],
            orderedItems: items,
            tappedItem: items[2],
            isShiftPressed: false,
            isCommandPressed: false
        )

        XCTAssertEqual(next, [items[2].objectID])
    }

    func testSingleClickOnOnlySelectedItemClearsSelection() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 3, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[1].objectID],
            orderedItems: items,
            tappedItem: items[1],
            isShiftPressed: false,
            isCommandPressed: false
        )

        XCTAssertTrue(next.isEmpty)
    }

    func testCommandClickTogglesSelection() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 3, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[0].objectID],
            orderedItems: items,
            tappedItem: items[1],
            isShiftPressed: false,
            isCommandPressed: true
        )

        XCTAssertEqual(next, [items[0].objectID, items[1].objectID])
    }

    func testShiftClickSelectsRangeFromAnchor() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 6, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[1].objectID],
            orderedItems: items,
            tappedItem: items[4],
            isShiftPressed: true,
            isCommandPressed: false
        )

        let expected: Set<NSManagedObjectID> = [
            items[1].objectID,
            items[2].objectID,
            items[3].objectID,
            items[4].objectID,
        ]
        XCTAssertEqual(next, expected)
    }

    private func makeItems(count: Int, in context: NSManagedObjectContext) -> [ClipItem] {
        let entity = NSEntityDescription.entity(forEntityName: "ClipItem", in: context)!
        return (0..<count).map { index in
            let item = ClipItem(entity: entity, insertInto: context)
            item.id = UUID()
            item.createdAt = Date().addingTimeInterval(TimeInterval(-index))
            item.modifiedAt = item.createdAt
            item.displayOrder = 0
            item.sourceAppBundleID = nil
            item.sourceAppName = nil
            item.itemType = 0
            item.primaryText = "Item \(index)"
            item.customTitle = nil
            item.searchableText = nil
            item.contentHash = "hash-\(index)"
            item.isSensitive = false
            item.isTransient = false
            item.needsLinkPreview = false
            item.thumbnailPath = nil
            item.byteCount = 0
            item.isUserCreated = false
            item.isPinned = false
            return item
        }
    }
}
