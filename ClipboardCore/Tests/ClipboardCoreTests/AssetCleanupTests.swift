import XCTest
@testable import ClipboardCore

final class AssetCleanupTests: XCTestCase {
    func testDeleteItemRemovesAssetFiles() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        let assetStore = AssetStore(baseURL: tempDir)
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .png,
                    uti: "public.png",
                    data: Data(repeating: 1, count: 300_000),
                    fileExtension: "png",
                    displayOrder: 0
                )
            ],
            primaryText: "Image",
            itemType: .image
        )

        let item = try store.createItem(payload: payload)
        let rep = try XCTUnwrap(item.representations?.first)
        let assetRef = try XCTUnwrap(rep.assetRef)
        let assetURL = assetStore.urlForAsset(assetRef, fileExtension: rep.fileExtension)
        XCTAssertTrue(fileManager.fileExists(atPath: assetURL.path))

        try store.deleteItem(objectID: item.objectID)
        XCTAssertFalse(fileManager.fileExists(atPath: assetURL.path))

        try? fileManager.removeItem(at: tempDir)
    }

    func testThumbnailCleanupOnDelete() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        let assetStore = AssetStore(baseURL: tempDir)
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        let item = try store.createTextItem(text: "Thumb")
        try store.updateThumbnail(objectID: item.objectID, data: Data(repeating: 2, count: 512))

        let refreshed = try store.fetchRecentItems(limit: 1).first
        let thumbnailPath = try XCTUnwrap(refreshed?.thumbnailPath)
        XCTAssertTrue(fileManager.fileExists(atPath: thumbnailPath))

        try store.deleteItem(objectID: item.objectID)
        XCTAssertFalse(fileManager.fileExists(atPath: thumbnailPath))

        try? fileManager.removeItem(at: tempDir)
    }
}
