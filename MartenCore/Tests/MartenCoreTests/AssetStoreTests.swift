import XCTest
@testable import MartenCore

final class AssetStoreTests: XCTestCase {
    func testStoreLoadDeleteAsset() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        let assetStore = AssetStore(baseURL: tempDir)
        let payload = Data("AssetData".utf8)
        let assetRef = try assetStore.store(data: payload, fileExtension: "txt")

        let loaded = try assetStore.load(assetRef: assetRef, fileExtension: "txt")
        XCTAssertEqual(loaded, payload)

        try assetStore.delete(assetRef: assetRef, fileExtension: "txt")
        XCTAssertThrowsError(try assetStore.load(assetRef: assetRef, fileExtension: "txt"))

        try? fileManager.removeItem(at: tempDir)
    }
}
