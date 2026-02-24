import MartenCore
@testable import MartenIOSApp
import Foundation
import XCTest

final class ClipItemCommandServiceTests: XCTestCase {
    func testMoveItemsMovesAllItemsToTargetPinboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let source = try store.createPinboard(name: "Source", colorHex: "#222222")
        let target = try store.createPinboard(name: "Target", colorHex: "#0099FF")
        let first = try store.createTextItem(text: "First")
        let second = try store.createTextItem(text: "Second")

        try store.addItem(objectID: first.objectID, toPinboard: source.objectID)
        try store.addItem(objectID: second.objectID, toPinboard: source.objectID)

        try await service.moveItems(
            objectIDs: [first.objectID, second.objectID],
            toPinboardID: target.objectID
        )

        let movedItems = try [first.objectID, second.objectID].map {
            try persistence.viewContext.existingObject(with: $0) as! ClipItem
        }

        for item in movedItems {
            let customPinboards = Set((item.pinboards ?? []).filter { !$0.isSystemMarten }.map(\.id))
            XCTAssertEqual(customPinboards, Set([target.id]))
        }
    }

    func testDeleteItemsRemovesProvidedItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let first = try store.createTextItem(text: "Delete me 1")
        let second = try store.createTextItem(text: "Delete me 2")

        try await service.deleteItems(objectIDs: [first.objectID, second.objectID])

        let remaining = try store.fetchRecentItems(limit: 10)
        let deletedIDs = Set([first.objectID, second.objectID])
        XCTAssertTrue(remaining.allSatisfy { !deletedIDs.contains($0.objectID) })
    }

    func testCreatePinboardStoresPinboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        try await service.createPinboard(name: "Recipes", colorHex: "#FF5500", iconName: "fork.knife")

        let pinboards = try persistence.viewContext.fetch(Pinboard.fetchRequest())
        let created = pinboards.first(where: { $0.name == "Recipes" })
        XCTAssertNotNil(created)
        XCTAssertEqual(created?.colorHex, "#FF5500")
        XCTAssertEqual(created?.iconName, "fork.knife")
    }

    func testReorderPinboardsUpdatesSortOrder() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let first = try store.createPinboard(name: "A", colorHex: "#111111")
        let second = try store.createPinboard(name: "B", colorHex: "#222222")

        // Reverse the order
        try await service.reorderPinboards(orderedIDs: [second.objectID, first.objectID])

        let reloadedFirst = try persistence.viewContext.existingObject(with: first.objectID) as! Pinboard
        let reloadedSecond = try persistence.viewContext.existingObject(with: second.objectID) as! Pinboard
        XCTAssertTrue(reloadedSecond.sortOrder < reloadedFirst.sortOrder)
    }

    func testRemoveItemsFromPinboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let pinboard = try store.createPinboard(name: "Temp", colorHex: "#333333")
        let item = try store.createTextItem(text: "Remove me")
        try store.addItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        try await service.removeItems(objectIDs: [item.objectID], fromPinboardID: pinboard.objectID)

        let reloaded = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        let customPinboards = (reloaded.pinboards ?? []).filter { !$0.isSystemMarten }
        XCTAssertFalse(customPinboards.contains(where: { $0.objectID == pinboard.objectID }))
    }

    func testRemoveItemsWithEmptyArrayIsNoop() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let pinboard = try store.createPinboard(name: "Empty", colorHex: "#444444")

        // Should not throw
        try await service.removeItems(objectIDs: [], fromPinboardID: pinboard.objectID)
    }

    func testMarkItemsUsedUpdatesAllProvidedItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let first = try store.createTextItem(text: "Use me 1")
        let second = try store.createTextItem(text: "Use me 2")

        let dateBefore = Date()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await service.markItemsUsed(objectIDs: [first.objectID, second.objectID])

        let reloadedFirst = try persistence.viewContext.existingObject(with: first.objectID) as! ClipItem
        let reloadedSecond = try persistence.viewContext.existingObject(with: second.objectID) as! ClipItem
        XCTAssertGreaterThan(reloadedFirst.modifiedAt, dateBefore)
        XCTAssertGreaterThan(reloadedSecond.modifiedAt, dateBefore)
    }

    func testDeleteItemsWithEmptyArrayIsNoop() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        // Should not throw
        try await service.deleteItems(objectIDs: [])
    }

    func testMoveItemsWithEmptyArrayIsNoop() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let pinboard = try store.createPinboard(name: "Target", colorHex: "#555555")

        // Should not throw
        try await service.moveItems(objectIDs: [], toPinboardID: pinboard.objectID)
    }

    func testUpdateRichTextItemPersistsPlainAndStyledContent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let item = try store.createTextItem(text: "Original text")
        let attributed = NSAttributedString(string: "Updated rich text")
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        try await service.updateRichTextItem(
            objectID: item.objectID,
            newText: "Updated rich text",
            rtfData: rtfData
        )

        let updated = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        XCTAssertEqual(updated.plainTextContent, "Updated rich text")
        XCTAssertNotNil(updated.styledTextContent)
    }

    func testUpdateTextItemPersistsNewPlainText() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = ClipItemCommandService(store: store)

        let item = try store.createTextItem(text: "Old value")

        try await service.updateTextItem(
            objectID: item.objectID,
            newText: "let sum = a + b"
        )

        let updated = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        XCTAssertEqual(updated.plainTextContent, "let sum = a + b")
    }
}
