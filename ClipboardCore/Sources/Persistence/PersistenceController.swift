import CoreData
import Foundation

public final class PersistenceController {
    public static let shared = PersistenceController()

    public static var modelURL: URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: "Paste", withExtension: "momd", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Paste", withExtension: "mom", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Paste", withExtension: "momd")
            ?? bundle.url(forResource: "Paste", withExtension: "mom")
    }

    public let container: NSPersistentContainer

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    public init(inMemory: Bool = false, storeURL: URL? = nil) {
        let bundle = Bundle.module
        let modelURL =
            bundle.url(forResource: "Paste", withExtension: "momd", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Paste", withExtension: "mom", subdirectory: "DataModel")
            ?? bundle.url(forResource: "Paste", withExtension: "momd")
            ?? bundle.url(forResource: "Paste", withExtension: "mom")

        guard let modelURL else {
            fatalError("Missing Core Data model resource Paste.momd")
        }

        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model from \(modelURL.path)")
        }

        container = NSPersistentContainer(name: "Paste", managedObjectModel: model)

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
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load persistent stores: \(error)")
            }
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
        let appSupportURL = baseURL.appendingPathComponent("Paste", isDirectory: true)

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(
                at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        return appSupportURL.appendingPathComponent("ClipboardCore.sqlite")
    }
}
