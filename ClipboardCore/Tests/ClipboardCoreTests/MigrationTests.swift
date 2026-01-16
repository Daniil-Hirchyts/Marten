import CoreData
import XCTest

@testable import ClipboardCore

final class MigrationTests: XCTestCase {
    private enum MigrationError: Error {
        case missingModelBundle
        case missingModelVersion(String)
        case modelLoadFailed(String)
    }

    func testLightweightMigrationFromV1ToV2PreservesData() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: tempDir, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("ClipboardCore.sqlite")

        let v1Model = try loadModelVersion(named: "Paste")
        try seedStore(at: storeURL, model: v1Model)

        let v2Model = try loadModelVersion(named: "PasteV2")
        let container = NSPersistentContainer(name: "Paste", managedObjectModel: v2Model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(
            true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        let loadExpectation = expectation(description: "load v2 store")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 5)
        if let loadError {
            throw loadError
        }

        let context = container.viewContext
        let request = ClipItem.fetchRequest()
        let items = try context.fetch(request)
        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.primaryText, "Hello world")
        XCTAssertEqual(item.contentHash, "hash-1")
        XCTAssertEqual(item.isPinned, true)

        let pinboard = try XCTUnwrap(item.pinboards?.first)
        XCTAssertEqual(pinboard.name, "Favorites")
        XCTAssertEqual(pinboard.colorHex, "#FF00AA")

        XCTAssertNil(item.value(forKey: "sourceAppVersion") as? String)
    }

    private func seedStore(at storeURL: URL, model: NSManagedObjectModel) throws {
        let container = NSPersistentContainer(name: "Paste", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]

        let loadExpectation = expectation(description: "load v1 store")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 5)
        if let loadError {
            throw loadError
        }

        let context = container.viewContext
        let item = ClipItem(context: context)
        item.id = UUID()
        item.createdAt = Date(timeIntervalSince1970: 1)
        item.modifiedAt = Date(timeIntervalSince1970: 2)
        item.displayOrder = 1
        item.sourceAppBundleID = "com.example.app"
        item.sourceAppName = "Example"
        item.itemType = 0
        item.primaryText = "Hello world"
        item.customTitle = "Hello world"
        item.searchableText = "Hello world"
        item.contentHash = "hash-1"
        item.isSensitive = false
        item.isTransient = false
        item.needsLinkPreview = false
        item.byteCount = 42
        item.isUserCreated = true
        item.isPinned = true

        let pinboard = Pinboard(context: context)
        pinboard.id = UUID()
        pinboard.name = "Favorites"
        pinboard.colorHex = "#FF00AA"
        pinboard.sortOrder = 1
        pinboard.isSystemClipboard = false
        pinboard.createdAt = Date(timeIntervalSince1970: 1)

        item.addToPinboards(pinboard)

        try context.save()
    }

    private func loadModelVersion(named name: String) throws -> NSManagedObjectModel {
        let momdURL = try pasteMomdURL()
        let modelURL = momdURL.appendingPathComponent("\(name).mom")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw MigrationError.missingModelVersion("\(name) at \(modelURL.path)")
        }

        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw MigrationError.modelLoadFailed(name)
        }

        return model
    }

    private func pasteMomdURL() throws -> URL {
        if let url = PersistenceController.modelURL {
            return url
        }

        let primaryBundles = [
            Bundle(for: MigrationTests.self),
            Bundle(for: PersistenceController.self),
            Bundle.main,
        ]

        for bundle in primaryBundles {
            if let url = bundle.url(
                forResource: "Paste", withExtension: "momd", subdirectory: "DataModel")
                ?? bundle.url(forResource: "Paste", withExtension: "momd")
            {
                return url
            }
        }

        let bundles = Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            if let url = bundle.url(
                forResource: "Paste", withExtension: "momd", subdirectory: "DataModel")
                ?? bundle.url(forResource: "Paste", withExtension: "momd")
            {
                return url
            }
        }

        for bundle in primaryBundles {
            if let resourceURL = bundle.resourceURL,
                let momdURL = findMomd(in: resourceURL)
            {
                return momdURL
            }
        }

        throw MigrationError.missingModelBundle
    }

    private func findMomd(in root: URL) -> URL? {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.lastPathComponent == "Paste.momd" {
                return url
            }
        }

        return nil
    }
}
