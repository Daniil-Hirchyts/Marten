import MartenCore
@testable import MartenIOSApp
import XCTest

final class WidgetTimelineServiceTests: XCTestCase {
    func testRecentEntriesMapsItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Widget Item", isUserCreated: true)

        let service = WidgetTimelineService(persistenceController: persistence)
        let entries = try await service.recentEntries(limit: 5)

        XCTAssertTrue(entries.contains(where: { $0.id == item.id }))
        XCTAssertTrue(entries.contains(where: { $0.deepLinkURL.absoluteString.contains(item.id.uuidString) }))
    }

    func testPinboardEntriesFiltersByPinboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Pinned", colorHex: "#AA7700")
        let item = try store.createTextItem(text: "Pinned Item", isUserCreated: true)
        try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        let service = WidgetTimelineService(persistenceController: persistence)
        let entries = try await service.entries(forPinboardID: pinboard.id, limit: 5)

        XCTAssertTrue(entries.contains(where: { $0.id == item.id }))
    }
}
