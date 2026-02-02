import CoreData
import Foundation

final class ClipItemUsageService {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func markItemUsed(objectID: NSManagedObjectID, now: Date = Date()) throws {
        try markItemsUsed(objectIDs: [objectID], now: now)
    }

    func markItemsUsed(objectIDs: [NSManagedObjectID], now: Date = Date()) throws {
        guard !objectIDs.isEmpty else { return }

        let context = persistence.newBackgroundContext()
        let baseOrder = currentDisplayOrder(reference: now) + Int64(objectIDs.count)

        try context.performAndWaitThrowing {
            for (index, objectID) in objectIDs.enumerated() {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }

                item.modifiedAt = now
                item.displayOrder = baseOrder - Int64(index)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        try refreshItemsInViewContext(objectIDs: objectIDs)
    }

    func reorderItems(objectIDs: [NSManagedObjectID]) throws {
        guard !objectIDs.isEmpty else { return }

        let now = Date()
        let baseOrder = currentDisplayOrder(reference: now) + Int64(objectIDs.count)
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            for (index, objectID) in objectIDs.enumerated() {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }

                item.displayOrder = baseOrder - Int64(index)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        try refreshItemsInViewContext(objectIDs: objectIDs)
    }

    private func refreshItemsInViewContext(objectIDs: [NSManagedObjectID]) throws {
        let viewContext = persistence.viewContext

        try viewContext.performAndWaitThrowing {
            for objectID in objectIDs {
                if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                    viewContext.refresh(item, mergeChanges: true)
                }
            }
        }
    }

    private func currentDisplayOrder(reference: Date = Date()) -> Int64 {
        Int64(reference.timeIntervalSince1970 * 1000)
    }
}

extension ClipItemUsageService: @unchecked Sendable {}
