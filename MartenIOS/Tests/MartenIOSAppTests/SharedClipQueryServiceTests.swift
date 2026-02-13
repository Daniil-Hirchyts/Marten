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
        XCTAssertTrue(results.allSatisfy { $0.modifiedAt >= $0.createdAt })
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

    func testRecentItemsMapsLinkPreviewMetadata() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let url = URL(string: "https://example.com/path")!
        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: "public.url",
                        text: url.absoluteString,
                        displayOrder: 0
                    )
                ],
                primaryText: url.absoluteString,
                itemType: .url,
                needsLinkPreview: true
            ),
            isUserCreated: true
        )

        let fetchedAt = Date()
        try store.updateLinkPreview(
            objectID: item.objectID,
            payload: LinkPreviewPayload(
                url: url,
                title: "Example Title",
                siteName: "Example Site",
                summary: "Summary",
                imageData: nil,
                imageURL: "https://cdn.example.com/image.png",
                fetchedAt: fetchedAt
            )
        )

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.recentItems(limit: 10)
        guard let summary = results.first(where: { $0.id == item.id }) else {
            XCTFail("Expected URL summary")
            return
        }

        XCTAssertNotNil(summary.linkPreview)
        XCTAssertEqual(summary.linkPreview?.title, "Example Title")
        XCTAssertEqual(summary.linkPreview?.siteName, "Example Site")
        XCTAssertEqual(summary.linkPreview?.imageURL, "https://cdn.example.com/image.png")
        XCTAssertEqual(summary.linkPreview?.fetchedAt, fetchedAt)
    }

    func testRecentItemsMapsFileColorAndThumbnailMetadata() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let filePath = "/private/var/mobile/Documents/report.pdf"
        let fileItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .fileURL,
                        uti: "public.file-url",
                        text: filePath,
                        displayOrder: 0
                    )
                ],
                primaryText: filePath,
                itemType: .file
            ),
            isUserCreated: true
        )

        let colorItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("0x12abef")],
                primaryText: "0x12abef",
                itemType: .color
            ),
            isUserCreated: true
        )

        let imageItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Image")],
                primaryText: "Image",
                itemType: .image
            ),
            isUserCreated: true
        )
        try store.updateThumbnail(
            objectID: imageItem.objectID,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            fileExtension: "png"
        )

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.recentItems(limit: 20)

        guard let fileSummary = results.first(where: { $0.id == fileItem.id }) else {
            XCTFail("Expected file summary")
            return
        }
        guard let colorSummary = results.first(where: { $0.id == colorItem.id }) else {
            XCTFail("Expected color summary")
            return
        }
        guard let imageSummary = results.first(where: { $0.id == imageItem.id }) else {
            XCTFail("Expected image summary")
            return
        }

        XCTAssertEqual(fileSummary.fileName, "report.pdf")
        XCTAssertGreaterThanOrEqual(fileSummary.byteCount, 0)
        XCTAssertEqual(colorSummary.colorHex, "#12ABEF")
        XCTAssertNotNil(imageSummary.thumbnailPath)
    }

    func testRecentItemsMapsImageThumbnailPathFromImageRepresentationData() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let pngData = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBAAHTVq0AAAAASUVORK5CYII="
            )
        )

        let imageItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .png,
                        uti: "public.png",
                        data: pngData,
                        fileExtension: "png",
                        displayOrder: 0
                    )
                ],
                primaryText: "Image",
                itemType: .image
            ),
            isUserCreated: true
        )

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.recentItems(limit: 20)

        guard let imageSummary = results.first(where: { $0.id == imageItem.id }) else {
            XCTFail("Expected image summary")
            return
        }

        guard let thumbnailPath = imageSummary.thumbnailPath else {
            XCTFail("Expected thumbnail path derived from image representation data")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailPath))
    }
}
