import XCTest
@testable import MartenCore

final class ClipItemStoreTests: XCTestCase {
    private var pngFixtureData: Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+yF9sAAAAASUVORK5CYII="
        )!
    }

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

    func testCreateImageItemsUseBinaryHashInsteadOfPlaceholderTitle() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let first = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .png,
                        uti: "public.png",
                        data: Data([0x01, 0x02, 0x03]),
                        fileExtension: "png"
                    )
                ],
                primaryText: "Image",
                itemType: .image
            )
        )

        let second = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .png,
                        uti: "public.png",
                        data: Data([0x04, 0x05, 0x06]),
                        fileExtension: "png"
                    )
                ],
                primaryText: "Image",
                itemType: .image
            )
        )

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(first.objectID, second.objectID)
        XCTAssertNotEqual(first.contentHash, second.contentHash)
    }

    func testBinaryContentHashBackfillRepairsLegacyImageHashes() throws {
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
        let legacyImageData = Data([0x0A, 0x0B, 0x0C])
        let legacyHash = Data("Image".utf8).sha256Hex()

        let objectID = try persistence.viewContext.performAndWaitThrowing { () -> NSManagedObjectID in
            let item = ClipItem(context: persistence.viewContext)
            item.id = UUID()
            item.createdAt = Date()
            item.modifiedAt = Date()
            item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
            item.itemTypeValue = .image
            item.primaryText = "Image"
            item.searchableText = "image"
            item.contentHash = legacyHash
            item.isSensitive = false
            item.isTransient = false
            item.needsLinkPreview = false
            item.byteCount = Int64(legacyImageData.count)
            item.isUserCreated = true
            item.isPinned = false

            let representation = ClipRepresentation(context: persistence.viewContext)
            representation.id = UUID()
            representation.uti = "public.png"
            representation.kindValue = .png
            representation.displayOrder = 0
            representation.fileExtension = "png"
            representation.assetRef = try assetStore.store(data: legacyImageData, fileExtension: "png")
            representation.byteCount = Int64(legacyImageData.count)
            representation.clipItem = item
            item.addToRepresentations(representation)

            try persistence.viewContext.save()
            return item.objectID
        }

        let updatedCount = try repository.backfillBinaryContentHashes()
        XCTAssertEqual(updatedCount, 1)

        persistence.viewContext.refreshAllObjects()
        try persistence.viewContext.performAndWaitThrowing {
            guard let item = try persistence.viewContext.existingObject(with: objectID) as? ClipItem else {
                XCTFail("Expected legacy image item to exist")
                return
            }

            XCTAssertEqual(item.contentHash, legacyImageData.sha256Hex())
        }
    }

    func testImageFileURLBackfillConvertsLegacyImagePathIntoAsset() throws {
        let persistence = PersistenceController(inMemory: true)
        let tempAssetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempAssetDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempAssetDir) }

        let sourceImageURL = tempAssetDir.appendingPathComponent("legacy-image").appendingPathExtension("png")
        try pngFixtureData.write(to: sourceImageURL)

        let bookmarkData = try sourceImageURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let assetStore = AssetStore(baseURL: tempAssetDir.appendingPathComponent("assets", isDirectory: true))
        let repository = ClipItemRepository(persistence: persistence, assetStore: assetStore)

        _ = try repository.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .fileURL,
                        uti: "public.file-url",
                        text: sourceImageURL.path,
                        data: bookmarkData,
                        fileExtension: "png"
                    )
                ],
                primaryText: sourceImageURL.lastPathComponent,
                itemType: .image
            )
        )

        let repairedCount = try repository.backfillImageFileURLRepresentations()
        XCTAssertEqual(repairedCount, 1)

        let repairedItem = try XCTUnwrap(repository.fetchRecentItems(limit: 1).first)
        let repairedRepresentation = try XCTUnwrap(repairedItem.representations?.first)
        XCTAssertEqual(repairedRepresentation.kindValue, .png)
        XCTAssertEqual(repairedRepresentation.fileExtension, "png")
        XCTAssertNotNil(repairedRepresentation.assetRef)
        XCTAssertNil(repairedRepresentation.textData)
        XCTAssertNil(repairedRepresentation.binaryData)
        XCTAssertEqual(repairedItem.contentHash, pngFixtureData.sha256Hex())

        let repairedAssetRef = try XCTUnwrap(repairedRepresentation.assetRef)
        XCTAssertEqual(
            try assetStore.load(assetRef: repairedAssetRef, fileExtension: repairedRepresentation.fileExtension),
            pngFixtureData
        )
    }

    func testCountItemsMissingRepresentationsDetectsCorruptItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = ClipItemRepository(persistence: persistence)

        try persistence.viewContext.performAndWaitThrowing {
            let item = ClipItem(context: persistence.viewContext)
            item.id = UUID()
            item.createdAt = Date()
            item.modifiedAt = Date()
            item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
            item.itemTypeValue = .image
            item.primaryText = "Image"
            item.searchableText = "image"
            item.contentHash = UUID().uuidString
            item.isSensitive = false
            item.isTransient = false
            item.needsLinkPreview = false
            item.byteCount = 123
            item.isUserCreated = true
            item.isPinned = false
            try persistence.viewContext.save()
        }

        XCTAssertEqual(try repository.countItemsMissingRepresentations(), 1)
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
