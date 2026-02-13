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
        let resolvedSourceApp = resolveSourceAppInfo(sourceApp)
        var savedCount = 0

        for payload in payloads {
            let item = try store.createItem(
                payload: payload,
                sourceApp: resolvedSourceApp,
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

    private func resolveSourceAppInfo(_ sourceApp: SourceAppInfo?) -> SourceAppInfo? {
        guard let sourceApp else { return nil }
        guard sourceApp.iconData == nil || sourceApp.iconData?.isEmpty == true else {
            return sourceApp
        }

        guard
            let bundleID = sourceApp.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleID.isEmpty,
            let cachedIconData = cachedSourceAppIconData(forBundleID: bundleID)
        else {
            return sourceApp
        }

        return SourceAppInfo(
            bundleID: sourceApp.bundleID,
            name: sourceApp.name,
            iconData: cachedIconData
        )
    }

    private func cachedSourceAppIconData(forBundleID bundleID: String) -> Data? {
        let context = persistenceController.viewContext
        var iconData: Data?
        context.performAndWait {
            let request = ClipItem.fetchRequest()
            request.fetchLimit = 20
            request.predicate = NSPredicate(
                format: "sourceAppBundleID == %@ AND sourceAppIconData != nil",
                bundleID
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "modifiedAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            if let results = try? context.fetch(request) {
                iconData = results.lazy
                    .compactMap(\.sourceAppIconData)
                    .first { !$0.isEmpty }
            }
        }
        return iconData
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
