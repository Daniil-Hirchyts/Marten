import CoreData
import Foundation
import MartenCore

public enum SharedClipCommandError: Error, Sendable, Equatable {
    case itemNotFound(UUID)
    case pinboardNotFound(UUID)
}

public actor SharedClipCommandService {
    private let store: ClipItemStore
    private let persistenceController: PersistenceController
    private let userDefaults: UserDefaults?

    public init(
        persistenceController: PersistenceController,
        store: ClipItemStore? = nil,
        userDefaults: UserDefaults? = UserDefaults(
            suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier
        )
    ) {
        self.persistenceController = persistenceController
        self.store = store ?? ClipItemStore(persistence: persistenceController)
        self.userDefaults = userDefaults
    }

    public func deleteItem(itemID: UUID) throws {
        let itemObjectID = try resolveItemObjectID(itemID)
        try store.deleteItem(objectID: itemObjectID)
        markKeyboardMutation()
    }

    public func moveItem(itemID: UUID, toPinboardID: UUID?) throws {
        let itemObjectID = try resolveItemObjectID(itemID)

        if let toPinboardID {
            let pinboardObjectID = try resolvePinboardObjectID(toPinboardID)
            try store.moveItem(objectID: itemObjectID, toPinboard: pinboardObjectID)
            markKeyboardMutation()
            return
        }

        let customPinboardObjectIDs = try resolveCustomPinboardObjectIDs(
            for: itemObjectID,
            itemID: itemID
        )
        for pinboardObjectID in customPinboardObjectIDs {
            try store.removeItem(objectID: itemObjectID, fromPinboard: pinboardObjectID)
        }
        markKeyboardMutation()
    }

    public func markItemUsed(itemID: UUID) throws {
        let itemObjectID = try resolveItemObjectID(itemID)
        try store.markItemUsed(objectID: itemObjectID)
        markKeyboardMutation()
    }

    private func resolveItemObjectID(_ itemID: UUID) throws -> NSManagedObjectID {
        let viewContext = persistenceController.viewContext
        return try viewContext.performAndWaitThrowing {
            let request = NSFetchRequest<ClipItem>(entityName: "ClipItem")
            request.predicate = NSPredicate(format: "id == %@", itemID as NSUUID)
            request.fetchLimit = 1

            guard let item = try viewContext.fetch(request).first else {
                throw SharedClipCommandError.itemNotFound(itemID)
            }
            return item.objectID
        }
    }

    private func resolvePinboardObjectID(_ pinboardID: UUID) throws -> NSManagedObjectID {
        let viewContext = persistenceController.viewContext
        return try viewContext.performAndWaitThrowing {
            let request = NSFetchRequest<Pinboard>(entityName: "Pinboard")
            request.predicate = NSPredicate(format: "id == %@", pinboardID as NSUUID)
            request.fetchLimit = 1

            guard let pinboard = try viewContext.fetch(request).first else {
                throw SharedClipCommandError.pinboardNotFound(pinboardID)
            }
            return pinboard.objectID
        }
    }

    private func resolveCustomPinboardObjectIDs(
        for itemObjectID: NSManagedObjectID,
        itemID: UUID
    ) throws -> [
        NSManagedObjectID
    ] {
        let viewContext = persistenceController.viewContext
        return try viewContext.performAndWaitThrowing {
            guard let item = try viewContext.existingObject(with: itemObjectID) as? ClipItem else {
                throw SharedClipCommandError.itemNotFound(itemID)
            }
            return (item.pinboards ?? [])
                .filter { !$0.isSystemMarten }
                .map(\.objectID)
        }
    }

    private func markKeyboardMutation() {
        userDefaults?.set(
            Date().timeIntervalSince1970,
            forKey: MartenIOSDefaults.keyboardLastMutationAtKey
        )
    }
}
