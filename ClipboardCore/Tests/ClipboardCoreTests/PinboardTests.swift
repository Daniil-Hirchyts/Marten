import XCTest
@testable import ClipboardCore

final class PinboardTests: XCTestCase {
    func testCreateRenameDeletePinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let pinboard = try store.createPinboard(name: "Ideas", colorHex: "#FF0000")
        XCTAssertEqual(pinboard.name, "Ideas")

        try store.renamePinboard(objectID: pinboard.objectID, name: "Thoughts", colorHex: "#00FF00")
        let pinboards = try store.fetchPinboards()
        let renamed = pinboards.first { $0.objectID == pinboard.objectID }
        XCTAssertEqual(renamed?.name, "Thoughts")
        XCTAssertEqual(renamed?.colorHex, "#00FF00")

        try store.deletePinboard(objectID: pinboard.objectID)
        let remaining = try store.fetchPinboards().filter { $0.objectID == pinboard.objectID }
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAddAndRemoveItemFromPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let pinboard = try store.createPinboard(name: "Work", colorHex: "#222222")
        let item = try store.createTextItem(text: "Note")

        try store.addItem(objectID: item.objectID, toPinboard: pinboard.objectID)
        let fetchedPinboard = try store.fetchPinboards().first { $0.objectID == pinboard.objectID }
        XCTAssertEqual(fetchedPinboard?.items?.count, 1)

        try store.removeItem(objectID: item.objectID, fromPinboard: pinboard.objectID)
        let updatedPinboard = try store.fetchPinboards().first { $0.objectID == pinboard.objectID }
        XCTAssertEqual(updatedPinboard?.items?.count ?? 0, 0)
    }

    func testMoveItemClearsOtherCustomPinboards() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let pinboardA = try store.createPinboard(name: "A", colorHex: "#111111")
        let pinboardB = try store.createPinboard(name: "B", colorHex: "#222222")
        let item = try store.createTextItem(text: "Move Me")

        try store.addItem(objectID: item.objectID, toPinboard: pinboardA.objectID)
        try store.addItem(objectID: item.objectID, toPinboard: pinboardB.objectID)
        try store.moveItem(objectID: item.objectID, toPinboard: pinboardA.objectID)

        let fetched = try persistence.viewContext.existingObject(with: item.objectID) as? ClipItem
        let customPinboards = fetched?.pinboards?.filter { !$0.isSystemClipboard } ?? []
        XCTAssertEqual(customPinboards.count, 1)
        XCTAssertEqual(customPinboards.first?.objectID, pinboardA.objectID)
    }
}
