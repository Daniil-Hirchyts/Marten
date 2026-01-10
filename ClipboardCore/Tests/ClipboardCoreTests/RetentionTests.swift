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
}
