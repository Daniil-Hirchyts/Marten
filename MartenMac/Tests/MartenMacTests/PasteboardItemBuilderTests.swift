import AppKit
import MartenCore
import UniformTypeIdentifiers
import XCTest

@testable import MartenMacServices

final class PasteboardItemBuilderTests: XCTestCase {
    func testBuildPasteboardItemForManagedFileUsesStagedExportURL() throws {
        let persistence = PersistenceController(inMemory: true)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let assetStore = AssetStore(baseURL: tempDirectory.appendingPathComponent("assets", isDirectory: true))
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)
        let fileData = Data("mac export file".utf8)
        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .custom,
                        uti: "public.plain-text",
                        data: fileData,
                        fileExtension: "txt"
                    )
                ],
                primaryText: "exported.txt",
                itemType: .file
            ),
            isUserCreated: true
        )

        let builder = PasteboardItemBuilder(assetStore: assetStore)
        let pasteboardItem = try builder.buildPasteboardItem(from: item)
        let fileURLString = try XCTUnwrap(
            pasteboardItem.string(forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier))
        )
        let fileURL = try XCTUnwrap(URL(string: fileURLString))

        XCTAssertEqual(fileURL.lastPathComponent, "exported.txt")
        XCTAssertEqual(try Data(contentsOf: fileURL), fileData)
    }
}
