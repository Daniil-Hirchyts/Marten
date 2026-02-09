import Foundation
import XCTest

@testable import MartenCore

final class LinkPreviewStoreTests: XCTestCase {
    func testUpdateLinkPreviewPersistsMetadataAndClearsNeedsFlag() throws {
        let persistence = PersistenceController(inMemory: true)
        let assetStore = AssetStore(baseURL: try makeTempDir())
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        let url = URL(string: "https://example.com/hello")!
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(kind: .url, uti: "public.url", text: url.absoluteString)
            ],
            primaryText: url.absoluteString,
            itemType: .url,
            needsLinkPreview: true
        )

        let item = try store.createItem(payload: payload)
        XCTAssertTrue(item.needsLinkPreview)

        let preview = LinkPreviewPayload(
            url: url,
            title: "Example",
            siteName: "example.com",
            summary: nil,
            imageData: Data([0x00, 0x01, 0x02]),
            iconData: nil,
            fetchedAt: Date(timeIntervalSince1970: 123)
        )

        try store.updateLinkPreview(objectID: item.objectID, payload: preview)

        let fetched = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        let updated = fetched[0]
        XCTAssertFalse(updated.needsLinkPreview)
        XCTAssertNotNil(updated.linkPreview)
        XCTAssertEqual(updated.linkPreview?.url, url.absoluteString)
        XCTAssertEqual(updated.linkPreview?.title, "Example")
        XCTAssertEqual(updated.linkPreview?.siteName, "example.com")
        XCTAssertEqual(updated.linkPreview?.fetchedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(updated.linkPreview?.fetchFailed, false)
        if let imagePath = updated.linkPreview?.imagePath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))
        } else {
            XCTFail("Expected imagePath")
        }
    }

    func testMarkLinkPreviewFetchFailedCreatesPreviewAndClearsNeedsFlag() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(
            persistence: persistence, assetStore: AssetStore(baseURL: try makeTempDir()))

        let url = URL(string: "https://example.com")!
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(kind: .url, uti: "public.url", text: url.absoluteString)
            ],
            primaryText: url.absoluteString,
            itemType: .url,
            needsLinkPreview: true
        )
        let item = try store.createItem(payload: payload)
        try store.markLinkPreviewFetchFailed(
            objectID: item.objectID, url: url, fetchedAt: Date(timeIntervalSince1970: 456))

        let fetched = try store.fetchRecentItems(limit: 10)
        let updated = fetched[0]
        XCTAssertFalse(updated.needsLinkPreview)
        XCTAssertEqual(updated.linkPreview?.url, url.absoluteString)
        XCTAssertEqual(updated.linkPreview?.fetchFailed, true)
        XCTAssertEqual(updated.linkPreview?.fetchedAt, Date(timeIntervalSince1970: 456))
    }

    func testFetchPendingLinkPreviewTargetsReturnsOnlyURLItemsNeedingPreview() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(
            persistence: persistence, assetStore: AssetStore(baseURL: try makeTempDir()))

        let urlA = URL(string: "https://a.example")!
        _ = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url, uti: "public.url", text: urlA.absoluteString)
                ],
                primaryText: urlA.absoluteString,
                itemType: .url,
                needsLinkPreview: true
            )
        )

        _ = try store.createItem(
            payload: ClipItemPayload(
                representations: [ClipRepresentationPayload.plainText("Hello")],
                primaryText: "Hello",
                itemType: .text,
                needsLinkPreview: true
            )
        )

        let pending = try store.fetchPendingLinkPreviewTargets(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].url, urlA)
    }

    func testDeleteItemRemovesLinkPreviewImageFile() throws {
        let persistence = PersistenceController(inMemory: true)
        let assetStore = AssetStore(baseURL: try makeTempDir())
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        let url = URL(string: "https://example.com")!
        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url, uti: "public.url", text: url.absoluteString)
                ],
                primaryText: url.absoluteString,
                itemType: .url,
                needsLinkPreview: true
            )
        )

        let preview = LinkPreviewPayload(
            url: url,
            title: "Example",
            siteName: "example.com",
            summary: nil,
            imageData: Data([0x10, 0x11]),
            iconData: nil,
            fetchedAt: Date()
        )
        try store.updateLinkPreview(objectID: item.objectID, payload: preview)

        let refreshed = try store.fetchRecentItems(limit: 10)[0]
        let imagePath = try XCTUnwrap(refreshed.linkPreview?.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        try store.deleteItem(objectID: item.objectID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
    }

    func testLinkPreviewFetcherDisabledThrowsWithoutNetwork() async throws {
        let fetcher = LinkPreviewFetcher(userDefaults: UserDefaults())
        fetcher.isEnabled = false
        await XCTAssertThrowsErrorAsync {
            _ = try await fetcher.fetchPreview(for: URL(string: "https://example.com")!)
        }
    }

    func testLinkPreviewFetcherRejectsNonHTTPURLsWithoutNetwork() async throws {
        let fetcher = LinkPreviewFetcher(userDefaults: UserDefaults())
        fetcher.isEnabled = true
        await XCTAssertThrowsErrorAsync {
            _ = try await fetcher.fetchPreview(for: URL(string: "file:///tmp/test.txt")!)
        }
    }

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
    }
}
