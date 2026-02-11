import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

final class LinkPreviewCoordinatorTests: XCTestCase {
    func testFetchPendingSuccessUpdatesPreview() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let url = "https://example.com"
        let created = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: "public.url",
                        text: url,
                        displayOrder: 0
                    )
                ],
                primaryText: url,
                itemType: .url,
                needsLinkPreview: true
            )
        )

        let coordinator = LinkPreviewCoordinator(
            store: store,
            fetcher: StubLinkPreviewFetcher(
                payload: LinkPreviewPayload(
                    url: URL(string: url)!,
                    title: "Example",
                    siteName: "example.com",
                    summary: nil,
                    imageData: nil,
                    iconData: nil,
                    fetchedAt: Date()
                )
            )
        )

        await coordinator.fetchPending(limit: 10)

        let updated = try persistence.viewContext.existingObject(with: created.objectID) as? ClipItem
        XCTAssertEqual(updated?.linkPreview?.title, "Example")
        XCTAssertEqual(updated?.needsLinkPreview, false)
    }

    func testFetchPendingFailureMarksPreviewFetchFailed() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let url = "https://example.com/fail"
        let created = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: "public.url",
                        text: url,
                        displayOrder: 0
                    )
                ],
                primaryText: url,
                itemType: .url,
                needsLinkPreview: true
            )
        )

        let coordinator = LinkPreviewCoordinator(
            store: store,
            fetcher: StubLinkPreviewFetcher(payload: nil)
        )

        await coordinator.fetchPending(limit: 10)

        let updated = try persistence.viewContext.existingObject(with: created.objectID) as? ClipItem
        XCTAssertEqual(updated?.linkPreview?.fetchFailed, true)
        XCTAssertEqual(updated?.needsLinkPreview, false)
    }
}

private struct StubLinkPreviewFetcher: LinkPreviewFetching {
    let payload: LinkPreviewPayload?

    func fetchPreview(for url: URL) async throws -> LinkPreviewPayload {
        guard let payload else { throw MockError.failed }
        return payload
    }
}

private enum MockError: Error {
    case failed
}
