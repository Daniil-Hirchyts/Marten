import CoreData
import Foundation
import MartenCore

public actor ShareExtensionSaveService {
    private let store: ClipItemStore
    private let persistenceController: PersistenceController

    public init(
        persistenceController: PersistenceController,
        assetStore: AssetStore? = nil,
        store: ClipItemStore? = nil
    ) {
        self.persistenceController = persistenceController
        if let store {
            self.store = store
        } else if let assetStore {
            self.store = ClipItemStore(
                persistence: persistenceController,
                assetStore: assetStore
            )
        } else {
            self.store = ClipItemStore(persistence: persistenceController)
        }
    }

    @discardableResult
    public func save(
        payloads: [ClipItemPayload],
        toPinboardID pinboardID: UUID?,
        sourceApp: SourceAppInfo? = nil
    ) throws -> Int {
        guard !payloads.isEmpty else { return 0 }

        let destinationObjectID = pinboardID.flatMap(resolvePinboardObjectID)
        var savedCount = 0

        for payload in payloads {
            let item = try store.createItem(
                payload: payload,
                sourceApp: sourceApp,
                isUserCreated: true
            )
            if let destinationObjectID {
                try store.moveItem(
                    objectID: item.objectID,
                    toPinboard: destinationObjectID
                )
            }
            savedCount += 1
        }

        return savedCount
    }

    private func resolvePinboardObjectID(_ pinboardID: UUID) -> NSManagedObjectID? {
        let context = persistenceController.viewContext
        var objectID: NSManagedObjectID?
        context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", pinboardID as NSUUID)
            objectID = try? context.fetch(request).first?.objectID
        }
        return objectID
    }
}
