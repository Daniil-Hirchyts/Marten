import XCTest
@testable import MartenCore

final class ClipItemStoreTests: XCTestCase {
    func testCreateTextItemInsertsClipItem() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createTextItem(text: "Hello world")
        XCTAssertEqual(item.primaryText, "Hello world")
        XCTAssertEqual(item.itemTypeValue, .text)
        XCTAssertFalse(item.contentHash.isEmpty)

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.representations?.count, 1)
    }

    func testCreateTextItemDeduplicatesByHash() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let first = try store.createTextItem(text: "Duplicate")
        let originalModifiedAt = first.modifiedAt

        let second = try store.createTextItem(text: "Duplicate")

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(first.objectID, second.objectID)
        XCTAssertTrue(second.modifiedAt >= originalModifiedAt)
    }
}
