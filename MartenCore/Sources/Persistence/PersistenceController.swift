import CoreData
import Foundation

public final class PersistenceController {
    public static let shared = PersistenceController()

    public static var modelURL: URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: "Marten", withExtension: "momd", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Marten", withExtension: "mom", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Marten", withExtension: "momd")
            ?? bundle.url(forResource: "Marten", withExtension: "mom")
    }

    public let container: NSPersistentContainer

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    public init(inMemory: Bool = false, storeURL: URL? = nil) {
        let modelURL = Self.modelURL

        guard let modelURL else {
            fatalError("Missing Core Data model resource Marten.momd")
        }

        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model from \(modelURL.path)")
        }

        container = NSPersistentContainer(name: "Marten", managedObjectModel: model)

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            description.url = storeURL ?? Self.defaultStoreURL()
        }

        description.setOption(
            true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        if !inMemory {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(
                true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError, !inMemory, let storeURL = description.url {
            // Attempt recovery by removing the corrupt store and retrying
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove write-ahead log and shared-memory files
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)

            var retryError: Error?
            container.loadPersistentStores { _, error in
                retryError = error
            }
            if let retryError {
                fatalError(
                    "Failed to load persistent stores after recovery attempt. "
                    + "Original: \(loadError). Retry: \(retryError)"
                )
            }
        } else if let loadError {
            fatalError("Failed to load persistent stores: \(loadError)")
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    public func saveViewContextIfNeeded() throws {
        guard viewContext.hasChanges else { return }
        try viewContext.save()
    }

    private static func defaultStoreURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let appSupportURL = baseURL.appendingPathComponent("Marten", isDirectory: true)

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(
                at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        return appSupportURL.appendingPathComponent("MartenCore.sqlite")
    }
}
