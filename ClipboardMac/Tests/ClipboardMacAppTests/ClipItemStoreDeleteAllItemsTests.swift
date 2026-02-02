import ClipboardCore
import Foundation
import XCTest

final class ClipItemStoreDeleteAllItemsTests: XCTestCase {
    func testDeleteAllItemsRemovesAllClipItems() throws {
        let persistence = PersistenceController(inMemory: true)

        let tempAssetsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assetStore = AssetStore(baseURL: tempAssetsURL)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)

        for i in 0..<450 {
            _ = try store.createTextItem(text: "Item \(i)")
        }

        try store.deleteAllItems()

        let viewContext = persistence.viewContext
        let remaining = try viewContext.performAndWaitThrowing {
            try viewContext.fetch(ClipItem.fetchRequest()).count
        }

        XCTAssertEqual(remaining, 0)
    }
}
