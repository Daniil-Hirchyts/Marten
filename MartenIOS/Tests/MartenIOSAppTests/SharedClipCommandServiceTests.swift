import MartenCore
@testable import MartenIOSApp
import XCTest

final class SharedClipCommandServiceTests: XCTestCase {
    func testDeleteItemDeletesByUUID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = SharedClipCommandService(persistenceController: persistence)

        let item = try store.createTextItem(text: "Delete me", isUserCreated: true)
        try await service.deleteItem(itemID: item.id)

        let remainingItems = try store.fetchRecentItems(limit: 20)
        XCTAssertFalse(remainingItems.contains(where: { $0.id == item.id }))
    }

    func testMoveItemToPinboardMovesByUUID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = SharedClipCommandService(persistenceController: persistence)

        let source = try store.createPinboard(name: "Source", colorHex: "#222222")
        let target = try store.createPinboard(name: "Target", colorHex: "#0099FF")
        let item = try store.createTextItem(text: "Move me", isUserCreated: true)
        try store.addItem(objectID: item.objectID, toPinboard: source.objectID)

        try await service.moveItem(itemID: item.id, toPinboardID: target.id)

        let reloaded = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        let customPinboards = Set((reloaded.pinboards ?? []).filter { !$0.isSystemMarten }.map(\.id))
        XCTAssertEqual(customPinboards, Set([target.id]))
    }

    func testMoveItemToAllRemovesCustomPinboards() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = SharedClipCommandService(persistenceController: persistence)

        let first = try store.createPinboard(name: "One", colorHex: "#AA0000")
        let second = try store.createPinboard(name: "Two", colorHex: "#00AA00")
        let item = try store.createTextItem(text: "Move to all", isUserCreated: true)
        try store.addItem(objectID: item.objectID, toPinboard: first.objectID)
        try store.addItem(objectID: item.objectID, toPinboard: second.objectID)

        try await service.moveItem(itemID: item.id, toPinboardID: nil)

        let reloaded = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        let customPinboards = (reloaded.pinboards ?? []).filter { !$0.isSystemMarten }
        XCTAssertTrue(customPinboards.isEmpty)
    }

    func testDeleteItemThrowsNotFoundForMissingItemID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let service = SharedClipCommandService(persistenceController: persistence)
        let missingID = UUID()

        do {
            try await service.deleteItem(itemID: missingID)
            XCTFail("Expected itemNotFound error")
        } catch let error as SharedClipCommandError {
            guard case .itemNotFound(let itemID) = error else {
                XCTFail("Expected itemNotFound but got \(error)")
                return
            }
            XCTAssertEqual(itemID, missingID)
        }
    }

    func testMoveItemThrowsNotFoundForMissingPinboardID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = SharedClipCommandService(persistenceController: persistence)
        let item = try store.createTextItem(text: "Move", isUserCreated: true)
        let missingPinboardID = UUID()

        do {
            try await service.moveItem(itemID: item.id, toPinboardID: missingPinboardID)
            XCTFail("Expected pinboardNotFound error")
        } catch let error as SharedClipCommandError {
            guard case .pinboardNotFound(let pinboardID) = error else {
                XCTFail("Expected pinboardNotFound but got \(error)")
                return
            }
            XCTAssertEqual(pinboardID, missingPinboardID)
        }
    }

    func testMarkItemUsedUpdatesItemUsageByUUID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let service = SharedClipCommandService(persistenceController: persistence)
        let item = try store.createTextItem(text: "Mark used", isUserCreated: true)

        let before = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        let beforeDate = before.modifiedAt

        try await Task.sleep(nanoseconds: 10_000_000)
        try await service.markItemUsed(itemID: item.id)

        let updated = try persistence.viewContext.existingObject(with: item.objectID) as! ClipItem
        XCTAssertGreaterThan(updated.modifiedAt, beforeDate)
    }
}
