import CoreData
import XCTest
@testable import MartenCore

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

    func testDeleteItemRemovesAssociatedStackEntries() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Stack cleanup")

        let context = persistence.viewContext
        let session =
            NSEntityDescription.insertNewObject(forEntityName: "StackSession", into: context)
            as! StackSession
        session.id = UUID()
        session.createdAt = Date()
        session.isActive = true
        session.separator = "\n"
        session.mode = StackMode.sequential.rawValue

        let entry =
            NSEntityDescription.insertNewObject(forEntityName: "StackEntry", into: context)
            as! StackEntry
        entry.id = UUID()
        entry.position = 0
        entry.addedAt = Date()
        entry.session = session
        entry.clipItem = item

        try context.save()
        XCTAssertEqual(try context.count(for: StackEntry.fetchRequest()), 1)

        try store.deleteItem(objectID: item.objectID)

        XCTAssertEqual(try context.count(for: StackEntry.fetchRequest()), 0)
    }
}
