import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

#if canImport(UIKit)
import UIKit

final class ItemCardDragPayloadBuilderTests: XCTestCase {
    func testFileDragRegistersManagedExportURL() throws {
        let persistence = PersistenceController(inMemory: true)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let previousShared = AssetStore.shared
        let assetStore = AssetStore(baseURL: tempDirectory.appendingPathComponent("assets", isDirectory: true))
        AssetStore.shared = assetStore
        defer { AssetStore.shared = previousShared }

        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)
        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .custom,
                        uti: "public.plain-text",
                        data: Data("drag me".utf8),
                        fileExtension: "txt"
                    )
                ],
                primaryText: "dragged.txt",
                itemType: .file
            ),
            isUserCreated: true
        )

        let builder = ItemCardDragPayloadBuilder()
        let dragItem = builder.dragItem(for: item.objectID, item: item)
        let provider = dragItem.itemProvider
        let expectation = expectation(description: "load file url")

        provider.loadObject(ofClass: NSURL.self) { object, error in
            XCTAssertNil(error)
            let url = object as URL?
            XCTAssertEqual(url?.lastPathComponent, "dragged.txt")
            XCTAssertEqual((try? Data(contentsOf: url ?? URL(fileURLWithPath: "/dev/null"))), Data("drag me".utf8))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
#endif
