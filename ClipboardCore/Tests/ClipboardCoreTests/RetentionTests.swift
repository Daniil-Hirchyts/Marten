import XCTest
@testable import ClipboardCore

final class RetentionTests: XCTestCase {
    func testCleanupExpiredItemsRemovesOldItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let oldItem = try store.createTextItem(text: "Old")
        let recentItem = try store.createTextItem(text: "Recent")

        let context = persistence.viewContext
        try context.performAndWaitThrowing {
            guard let oldInContext = try context.existingObject(with: oldItem.objectID) as? ClipItem else {
                XCTFail("Missing old item in view context")
                return
            }
            guard let recentInContext = try context.existingObject(with: recentItem.objectID) as? ClipItem else {
                XCTFail("Missing recent item in view context")
                return
            }

            oldInContext.createdAt = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
            oldInContext.modifiedAt = oldInContext.createdAt
            recentInContext.createdAt = Date()
            recentInContext.modifiedAt = recentInContext.createdAt
            try context.save()
        }

        let deleted = try store.cleanupExpiredItems(policy: .week, now: Date())
        XCTAssertEqual(deleted, 1)

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.primaryText, "Recent")
    }

    func testCleanupExpiredItemsKeepsItemsInCustomPinboards() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let archivePinboard = try store.createPinboard(name: "Archive", colorHex: "#123456")
        let oldPinnedToPinboard = try store.createTextItem(text: "Keep in pinboard")
        let oldHistoryOnlyItem = try store.createTextItem(text: "Delete from history")

        try store.addItem(objectID: oldPinnedToPinboard.objectID, toPinboard: archivePinboard.objectID)

        let context = persistence.viewContext
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        try context.performAndWaitThrowing {
            guard let oldPinned = try context.existingObject(with: oldPinnedToPinboard.objectID) as? ClipItem else {
                XCTFail("Missing pinboard item in view context")
                return
            }
            guard let oldHistoryOnly = try context.existingObject(with: oldHistoryOnlyItem.objectID) as? ClipItem else {
                XCTFail("Missing history-only item in view context")
                return
            }

            oldPinned.createdAt = oldDate
            oldPinned.modifiedAt = oldDate
            oldHistoryOnly.createdAt = oldDate
            oldHistoryOnly.modifiedAt = oldDate
            try context.save()
        }

        let deleted = try store.cleanupExpiredItems(policy: .week, now: Date())
        XCTAssertEqual(deleted, 1)

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertTrue(items.contains(where: { $0.objectID == oldPinnedToPinboard.objectID }))
        XCTAssertFalse(items.contains(where: { $0.objectID == oldHistoryOnlyItem.objectID }))

        let savedPinboard = try store.fetchPinboards().first { $0.objectID == archivePinboard.objectID }
        XCTAssertEqual(savedPinboard?.items?.count, 1)
    }
}
