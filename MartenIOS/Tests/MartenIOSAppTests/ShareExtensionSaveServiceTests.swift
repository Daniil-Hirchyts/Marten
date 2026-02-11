import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

final class ShareExtensionSaveServiceTests: XCTestCase {
    func testSaveWithZeroPayloadsReturnsZero() async throws {
        let fixture = StubStoreFixture()
        let service = ShareExtensionSaveService(
            persistenceController: fixture.persistence,
            store: fixture.store
        )

        let count = try await service.save(payloads: [], toPinboardID: nil)
        XCTAssertEqual(count, 0)
    }

    func testSaveWithSinglePayloadReturnsOne() async throws {
        let fixture = StubStoreFixture()
        let service = ShareExtensionSaveService(
            persistenceController: fixture.persistence,
            store: fixture.store
        )

        let payload = ClipItemPayload(
            representations: [.plainText("Shared text")],
            primaryText: "Shared text",
            itemType: .text
        )

        let count = try await service.save(payloads: [payload], toPinboardID: nil)
        XCTAssertEqual(count, 1)

        let items = try fixture.store.fetchRecentItems(limit: 10)
        XCTAssertTrue(items.contains(where: { $0.primaryText == "Shared text" }))
    }

    func testSaveWithMultiplePayloadsReturnsCorrectCount() async throws {
        let fixture = StubStoreFixture()
        let service = ShareExtensionSaveService(
            persistenceController: fixture.persistence,
            store: fixture.store
        )

        let payloads = (0..<3).map { i in
            ClipItemPayload(
                representations: [.plainText("Item \(i)")],
                primaryText: "Item \(i)",
                itemType: .text
            )
        }

        let count = try await service.save(payloads: payloads, toPinboardID: nil)
        XCTAssertEqual(count, 3)
    }

    func testSaveWithPinboardTargetMovesItemsToPinboard() async throws {
        let fixture = StubStoreFixture()
        let pinboard = try fixture.store.createPinboard(name: "Target", colorHex: "#FF0000")
        let service = ShareExtensionSaveService(
            persistenceController: fixture.persistence,
            store: fixture.store
        )

        let payload = ClipItemPayload(
            representations: [.plainText("Targeted text")],
            primaryText: "Targeted text",
            itemType: .text
        )

        let count = try await service.save(payloads: [payload], toPinboardID: pinboard.id)
        XCTAssertEqual(count, 1)

        let items = try fixture.store.fetchRecentItems(limit: 10)
        let saved = items.first { $0.primaryText == "Targeted text" }
        XCTAssertNotNil(saved)
        let pinboards = saved?.pinboards ?? []
        XCTAssertTrue(pinboards.contains(where: { $0.id == pinboard.id }))
    }

    func testSaveWithNilPinboardFallbackSavesToDefaultOnly() async throws {
        let fixture = StubStoreFixture()
        let service = ShareExtensionSaveService(
            persistenceController: fixture.persistence,
            store: fixture.store
        )

        let payload = ClipItemPayload(
            representations: [.plainText("No pinboard target")],
            primaryText: "No pinboard target",
            itemType: .text
        )

        let count = try await service.save(payloads: [payload], toPinboardID: nil)
        XCTAssertEqual(count, 1)
    }
}
