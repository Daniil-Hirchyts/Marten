import XCTest
@testable import MartenCore

final class RepresentationNormalizationTests: XCTestCase {
    func testCreateItemPreservesDisplayOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(kind: .plainText, uti: "public.utf8-plain-text", text: "Second", displayOrder: 1),
                ClipRepresentationPayload(kind: .plainText, uti: "public.utf8-plain-text", text: "First", displayOrder: 0)
            ],
            primaryText: "First",
            itemType: .text
        )

        let item = try store.createItem(payload: payload)
        let orders = item.representations?.map { $0.displayOrder } ?? []
        XCTAssertTrue(orders.contains(0))
        XCTAssertTrue(orders.contains(1))
    }

    func testSearchableTextFallbacksToRepresentationText() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(kind: .plainText, uti: "public.utf8-plain-text", text: "Fallback Text", displayOrder: 0)
            ],
            primaryText: nil,
            itemType: .text
        )

        let item = try store.createItem(payload: payload)
        XCTAssertEqual(item.searchableText, "fallback text")
    }
}
