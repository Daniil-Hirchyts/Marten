import XCTest
@testable import MartenCore

final class SearchTests: XCTestCase {
    func testSearchItemsReturnsMatches() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        _ = try store.createTextItem(text: "Alpha Bravo")
        _ = try store.createTextItem(text: "Charlie Delta")
        _ = try store.createTextItem(text: "Echo Foxtrot")

        let matches = try store.searchItems(query: "bravo")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.primaryText, "Alpha Bravo")
    }
}
