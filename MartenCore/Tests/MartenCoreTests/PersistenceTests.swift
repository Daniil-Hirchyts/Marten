import XCTest
@testable import MartenCore

final class PersistenceTests: XCTestCase {
    func testItemsPersistAcrossRestarts() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let storeURL = tempDir.appendingPathComponent("MartenCore.sqlite")

        do {
            let persistence = PersistenceController(inMemory: false, storeURL: storeURL)
            let store = ClipItemStore(persistence: persistence)
            _ = try store.createTextItem(text: "Persist me")
        }

        let persistence = PersistenceController(inMemory: false, storeURL: storeURL)
        let store = ClipItemStore(persistence: persistence)
        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)

        try? fileManager.removeItem(at: tempDir)
    }
}
