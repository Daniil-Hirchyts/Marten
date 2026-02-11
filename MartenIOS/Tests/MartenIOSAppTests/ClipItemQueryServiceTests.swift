import MartenCore
@testable import MartenIOSApp
import XCTest

final class ClipItemQueryServiceTests: XCTestCase {
    func testSearchWithEmptyQueryReturnsAllMatchingItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(text: "Alpha")
        _ = try store.createTextItem(text: "Bravo")

        let service = ClipItemQueryService(store: store)
        let results = try await service.search(request: ClipItemSearchRequest(query: ""))

        XCTAssertGreaterThanOrEqual(results.count, 2)
    }

    func testSearchWithTextQueryFiltersResults() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(text: "Hello world")
        _ = try store.createTextItem(text: "Goodbye")

        let service = ClipItemQueryService(store: store)
        let results = try await service.search(
            request: ClipItemSearchRequest(query: "Hello")
        )

        XCTAssertTrue(results.allSatisfy { $0.primaryText?.contains("Hello") == true })
    }

    func testSearchWithPinboardScopeFiltersResults() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Work", colorHex: "#0099FF")
        let included = try store.createTextItem(text: "Scoped item")
        _ = try store.createTextItem(text: "Unscoped item")
        try store.addItem(objectID: included.objectID, toPinboard: pinboard.objectID)

        let service = ClipItemQueryService(store: store)
        let results = try await service.search(
            request: ClipItemSearchRequest(pinboardID: pinboard.id)
        )

        XCTAssertTrue(results.contains(where: { $0.objectID == included.objectID }))
    }

    func testSearchLimitEnforcement() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        for i in 0..<20 {
            _ = try store.createTextItem(text: "Item \(i)")
        }

        let service = ClipItemQueryService(store: store)
        let results = try await service.search(
            request: ClipItemSearchRequest(query: "", limit: 5)
        )

        XCTAssertLessThanOrEqual(results.count, 5)
    }
}
