import XCTest
@testable import MartenCore

final class ClipItemStoreTests: XCTestCase {
    func testCreateTextItemInsertsClipItem() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createTextItem(text: "Hello world")
        XCTAssertEqual(item.primaryText, "Hello world")
        XCTAssertEqual(item.itemTypeValue, .text)
        XCTAssertFalse(item.contentHash.isEmpty)

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.representations?.count, 1)
    }

    func testCreateTextItemDeduplicatesByHash() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let first = try store.createTextItem(text: "Duplicate")
        let originalModifiedAt = first.modifiedAt

        let second = try store.createTextItem(text: "Duplicate")

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(first.objectID, second.objectID)
        XCTAssertTrue(second.modifiedAt >= originalModifiedAt)
    }

    func testUpdateItemTypeConvertsTextToURLAndNormalizes() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "example.com")

        let converted = try store.updateItemType(objectID: item.objectID, newType: .url)

        XCTAssertEqual(converted.itemTypeValue, .url)
        XCTAssertEqual(converted.primaryText, "https://example.com")
        XCTAssertTrue(converted.needsLinkPreview)
        XCTAssertEqual(converted.representations?.count, 1)
        XCTAssertEqual(converted.representations?.first?.kindValue, .url)
    }

    func testUpdateItemTypeRejectsRichTextConversion() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Simple note")

        XCTAssertThrowsError(try store.updateItemType(objectID: item.objectID, newType: .richText)) { error in
            XCTAssertEqual(error as? ClipItemStoreError, .unsupportedTypeConversion)
        }
    }

    func testUpdateItemTypeConvertsURLToTextAndClearsLinkPreview() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: "public.url",
                        text: "https://example.com"
                    )
                ],
                primaryText: "https://example.com",
                itemType: .url,
                needsLinkPreview: true
            )
        )

        try store.updateLinkPreview(
            objectID: item.objectID,
            payload: LinkPreviewPayload(
                url: URL(string: "https://example.com")!,
                title: "Example",
                siteName: "Example",
                summary: "Summary",
                imageData: nil,
                imageURL: nil,
                fetchedAt: Date()
            )
        )

        let converted = try store.updateItemType(objectID: item.objectID, newType: .text)

        XCTAssertEqual(converted.itemTypeValue, .text)
        XCTAssertEqual(converted.primaryText, "https://example.com")
        XCTAssertFalse(converted.needsLinkPreview)
        XCTAssertNil(converted.linkPreview)
        XCTAssertEqual(converted.representations?.count, 1)
        XCTAssertEqual(converted.representations?.first?.kindValue, .plainText)
    }

    func testUpdateItemTypeRejectsInvalidURLConversion() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "not a valid url with spaces")

        XCTAssertThrowsError(try store.updateItemType(objectID: item.objectID, newType: .url)) { error in
            XCTAssertEqual(error as? ClipItemStoreError, .invalidURLForTypeConversion)
        }
    }

    func testRepresentationAssetBackfillSkipsNonMigratableRowsWithoutLooping() throws {
        let persistence = PersistenceController(inMemory: true)
        let tempAssetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempAssetDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempAssetDir) }

        let assetStore = AssetStore(baseURL: tempAssetDir)
        let repository = ClipItemRepository(persistence: persistence, assetStore: assetStore)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)
        let seedItem = try store.createTextItem(text: "seed")

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            guard let item = try viewContext.existingObject(with: seedItem.objectID) as? ClipItem else {
                XCTFail("Expected seed item to exist")
                return
            }

            let nonMigratable = ClipRepresentation(context: viewContext)
            nonMigratable.id = UUID()
            nonMigratable.kindValue = .plainText
            nonMigratable.uti = "public.utf8-plain-text"
            nonMigratable.displayOrder = 10
            nonMigratable.binaryData = Data([1, 2, 3])
            nonMigratable.byteCount = 3
            nonMigratable.clipItem = item
            item.addToRepresentations(nonMigratable)

            let migratable = ClipRepresentation(context: viewContext)
            migratable.id = UUID()
            migratable.kindValue = .rtf
            migratable.uti = "public.rtf"
            migratable.displayOrder = 11
            migratable.fileExtension = "rtf"
            migratable.binaryData = Data([9, 8, 7, 6])
            migratable.byteCount = 4
            migratable.clipItem = item
            item.addToRepresentations(migratable)

            try viewContext.save()
        }

        let migratedCount = try repository.migrateSyncableBinaryRepresentationsToAssets()
        XCTAssertEqual(migratedCount, 1)

        viewContext.reset()
        try viewContext.performAndWaitThrowing {
            let request = ClipRepresentation.fetchRequest()
            let representations = try viewContext.fetch(request)

            let nonMigrated = try XCTUnwrap(representations.first(where: { $0.kindValue == .plainText && $0.binaryData != nil }))
            XCTAssertNil(nonMigrated.assetRef)

            let migrated = try XCTUnwrap(representations.first(where: { $0.kindValue == .rtf }))
            XCTAssertNil(migrated.binaryData)
            XCTAssertNotNil(migrated.assetRef)
        }

        // A second pass should finish immediately and report no additional work.
        let secondPassCount = try repository.migrateSyncableBinaryRepresentationsToAssets()
        XCTAssertEqual(secondPassCount, 0)
    }
}
