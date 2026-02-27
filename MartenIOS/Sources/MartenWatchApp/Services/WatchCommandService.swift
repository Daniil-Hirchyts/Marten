import CoreData
import Foundation
import MartenCore

enum WatchCommandError: Error, Sendable, Equatable {
    case emptyText
    case itemNotFound(UUID)
    case pinboardNotFound(UUID)
}

actor WatchCommandService {
    private let store: ClipItemStore
    private let persistenceController: PersistenceController
    private let martenSourceApp = SourceAppInfo(
        bundleID: SourceAppIdentity.martenBundleID,
        name: SourceAppIdentity.martenDisplayName
    )

    init(store: ClipItemStore, persistenceController: PersistenceController) {
        self.store = store
        self.persistenceController = persistenceController
    }

    func createTextItem(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        _ = try store.createTextItem(
            text: trimmed,
            sourceApp: martenSourceApp,
            isUserCreated: true
        )
    }

    func createTextItemReturningID(_ text: String) throws -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WatchCommandError.emptyText }

        let item = try store.createTextItem(
            text: trimmed,
            sourceApp: martenSourceApp,
            isUserCreated: true
        )
        return item.id
    }

    func markItemUsed(itemID: UUID) throws {
        let objectID = try resolveItemObjectID(itemID)
        try store.markItemUsed(objectID: objectID)
    }

    func deleteItem(itemID: UUID) throws {
        let objectID = try resolveItemObjectID(itemID)
        try store.deleteItem(objectID: objectID)
    }

    func togglePin(itemID: UUID) throws {
        let objectID = try resolveItemObjectID(itemID)
        try store.togglePin(objectID: objectID)
    }

    func updateTextItem(itemID: UUID, newText: String) throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let objectID = try resolveItemObjectID(itemID)
        _ = try store.updateTextItem(objectID: objectID, newText: trimmed)
    }

    func moveItem(itemID: UUID, toPinboardID pinboardID: UUID) throws {
        let itemObjectID = try resolveItemObjectID(itemID)
        let pinboardObjectID = try resolvePinboardObjectID(pinboardID)
        try store.moveItem(objectID: itemObjectID, toPinboard: pinboardObjectID)
    }

    func addItem(itemID: UUID, toPinboardID pinboardID: UUID) throws {
        let itemObjectID = try resolveItemObjectID(itemID)
        let pinboardObjectID = try resolvePinboardObjectID(pinboardID)
        try store.addItem(objectID: itemObjectID, toPinboard: pinboardObjectID)
    }

    func removeItem(itemID: UUID, fromPinboardID pinboardID: UUID) throws {
        let itemObjectID = try resolveItemObjectID(itemID)
        let pinboardObjectID = try resolvePinboardObjectID(pinboardID)
        try store.removeItem(objectID: itemObjectID, fromPinboard: pinboardObjectID)
    }

    private func resolveItemObjectID(_ itemID: UUID) throws -> NSManagedObjectID {
        let viewContext = persistenceController.viewContext
        return try viewContext.performAndWaitThrowing {
            let request = NSFetchRequest<ClipItem>(entityName: "ClipItem")
            request.predicate = NSPredicate(format: "id == %@", itemID as NSUUID)
            request.fetchLimit = 1

            guard let item = try viewContext.fetch(request).first else {
                throw WatchCommandError.itemNotFound(itemID)
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
                throw WatchCommandError.pinboardNotFound(pinboardID)
            }

            return pinboard.objectID
        }
    }
}
