import MartenCore
import CoreData
import XCTest

@testable import MartenMac

final class ItemSelectionHandlerTests: XCTestCase {
    func testSingleClickSelectsOnlyTappedItem() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 5, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [],
            currentAnchorID: nil,
            currentCursorID: nil,
            orderedItems: items,
            tappedItem: items[2],
            isShiftPressed: false,
            isCommandPressed: false
        )

        XCTAssertEqual(next.selectedIDs, [items[2].objectID])
        XCTAssertEqual(next.anchorID, items[2].objectID)
        XCTAssertEqual(next.cursorID, items[2].objectID)
    }

    func testSingleClickOnOnlySelectedItemKeepsSelection() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 3, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[1].objectID],
            currentAnchorID: items[1].objectID,
            currentCursorID: items[1].objectID,
            orderedItems: items,
            tappedItem: items[1],
            isShiftPressed: false,
            isCommandPressed: false
        )

        XCTAssertEqual(next.selectedIDs, [items[1].objectID])
        XCTAssertEqual(next.anchorID, items[1].objectID)
        XCTAssertEqual(next.cursorID, items[1].objectID)
    }

    func testCommandClickTogglesSelection() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 3, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[0].objectID],
            currentAnchorID: items[0].objectID,
            currentCursorID: items[0].objectID,
            orderedItems: items,
            tappedItem: items[1],
            isShiftPressed: false,
            isCommandPressed: true
        )

        XCTAssertEqual(next.selectedIDs, [items[0].objectID, items[1].objectID])
        XCTAssertEqual(next.anchorID, items[1].objectID)
        XCTAssertEqual(next.cursorID, items[1].objectID)
    }

    func testCommandClickToggleOffKeepsDeterministicEndpoint() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 3, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[0].objectID, items[1].objectID],
            currentAnchorID: items[0].objectID,
            currentCursorID: items[0].objectID,
            orderedItems: items,
            tappedItem: items[1],
            isShiftPressed: false,
            isCommandPressed: true
        )

        XCTAssertEqual(next.selectedIDs, [items[0].objectID])
        XCTAssertEqual(next.anchorID, items[0].objectID)
        XCTAssertEqual(next.cursorID, items[0].objectID)
    }

    func testShiftClickSelectsReplacementRangeFromAnchor() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 6, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[1].objectID, items[5].objectID],
            currentAnchorID: items[1].objectID,
            currentCursorID: items[1].objectID,
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
        XCTAssertEqual(next.selectedIDs, expected)
        XCTAssertEqual(next.anchorID, items[1].objectID)
        XCTAssertEqual(next.cursorID, items[4].objectID)
    }

    func testCommandShiftClickUnionsRange() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 6, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[0].objectID, items[5].objectID],
            currentAnchorID: items[0].objectID,
            currentCursorID: items[0].objectID,
            orderedItems: items,
            tappedItem: items[3],
            isShiftPressed: true,
            isCommandPressed: true
        )

        let expected: Set<NSManagedObjectID> = [
            items[0].objectID,
            items[1].objectID,
            items[2].objectID,
            items[3].objectID,
            items[5].objectID,
        ]
        XCTAssertEqual(next.selectedIDs, expected)
        XCTAssertEqual(next.anchorID, items[0].objectID)
        XCTAssertEqual(next.cursorID, items[3].objectID)
    }

    func testShiftUsesProvidedAnchorNotSetIterationOrder() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let items = makeItems(count: 6, in: context)
        try context.save()

        let handler = ItemSelectionHandler()
        let next = handler.updatedSelection(
            currentSelection: [items[0].objectID, items[4].objectID],
            currentAnchorID: items[4].objectID,
            currentCursorID: items[0].objectID,
            orderedItems: items,
            tappedItem: items[2],
            isShiftPressed: true,
            isCommandPressed: false
        )

        let expected: Set<NSManagedObjectID> = [
            items[2].objectID,
            items[3].objectID,
            items[4].objectID,
        ]
        XCTAssertEqual(next.selectedIDs, expected)
        XCTAssertEqual(next.anchorID, items[4].objectID)
        XCTAssertEqual(next.cursorID, items[2].objectID)
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
