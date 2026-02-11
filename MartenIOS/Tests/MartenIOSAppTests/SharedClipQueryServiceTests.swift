import MartenCore
@testable import MartenIOSApp
import XCTest

final class SharedClipQueryServiceTests: XCTestCase {
    func testRecentItemsReturnsMappedSummaries() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        _ = try store.createTextItem(text: "Alpha", isUserCreated: true)
        _ = try store.createTextItem(text: "Beta", isUserCreated: true)

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.recentItems(limit: 10)

        XCTAssertGreaterThanOrEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.insertionText.contains("Alpha") }))
        XCTAssertTrue(results.contains(where: { $0.insertionText.contains("Beta") }))
    }

    func testSearchItemsAppliesQuery() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        _ = try store.createTextItem(text: "Marten Search Needle", isUserCreated: true)
        _ = try store.createTextItem(text: "Unrelated", isUserCreated: true)

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.searchItems(query: "Needle", limit: 10)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].insertionText.contains("Needle"))
    }
}
