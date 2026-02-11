import CoreData
import Foundation

final class PinboardRepository {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func fetchPinboards() throws -> [Pinboard] {
        let context = persistence.viewContext
        var results: [Pinboard] = []

        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            results = try context.fetch(request)
        }

        return results
    }

    @discardableResult
    func createPinboard(name: String, colorHex: String, iconName: String? = nil) throws
        -> Pinboard
    {
        let context = persistence.newBackgroundContext()
        var createdObjectID: NSManagedObjectID?

        try context.performAndWaitThrowing {
            guard
                let pinboard = NSEntityDescription.insertNewObject(
                    forEntityName: "Pinboard",
                    into: context
                ) as? Pinboard
            else {
                throw ClipItemStoreError.creationFailed
            }

            pinboard.id = UUID()
            pinboard.name = name
            pinboard.colorHex = colorHex
            pinboard.sortOrder = Int16((try? nextPinboardSortOrder(in: context)) ?? 0)
            pinboard.isSystemMarten = false
            pinboard.createdAt = Date()
            pinboard.iconName = iconName

            try context.save()
            createdObjectID = pinboard.objectID
        }

        guard let objectID = createdObjectID else {
            throw ClipItemStoreError.creationFailed
        }

        let viewContext = persistence.viewContext
        var fetchedPinboard: Pinboard?

        try viewContext.performAndWaitThrowing {
            fetchedPinboard = try viewContext.existingObject(with: objectID) as? Pinboard
        }

        guard let pinboard = fetchedPinboard else {
            throw ClipItemStoreError.creationFailed
        }

        return pinboard
    }

    func renamePinboard(objectID: NSManagedObjectID, name: String, colorHex: String? = nil) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }

            pinboard.name = name
            if let colorHex {
                pinboard.colorHex = colorHex
            }
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let pinboard = try? viewContext.existingObject(with: objectID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    func updatePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }

            pinboard.name = name
            pinboard.colorHex = colorHex
            pinboard.iconName = iconName
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let pinboard = try? viewContext.existingObject(with: objectID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    func deletePinboard(objectID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }

            context.delete(pinboard)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func addItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard
                let item = try context.existingObject(with: objectID) as? ClipItem,
                let pinboard = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }

            try validateMixedMembership(item: item, targetPinboard: pinboard)
            item.addToPinboards(pinboard)
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
            if let pinboard = try? viewContext.existingObject(with: pinboardID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    func removeItem(objectID: NSManagedObjectID, fromPinboard pinboardID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard
                let item = try context.existingObject(with: objectID) as? ClipItem,
                let pinboard = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }

            item.removeFromPinboards(pinboard)
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
            if let pinboard = try? viewContext.existingObject(with: pinboardID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    func moveItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard
                let item = try context.existingObject(with: objectID) as? ClipItem,
                let target = try context.existingObject(with: pinboardID) as? Pinboard
            else {
                throw ClipItemStoreError.missingItem
            }

            for pinboard in item.pinboards ?? []
            where !pinboard.isSystemMarten && pinboard.objectID != target.objectID {
                item.removeFromPinboards(pinboard)
            }

            try validateMixedMembership(item: item, targetPinboard: target)
            item.addToPinboards(target)
            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                viewContext.refresh(item, mergeChanges: true)
            }
        }
    }

    func moveItems(objectIDs: [NSManagedObjectID], toPinboard pinboardID: NSManagedObjectID) throws {
        guard !objectIDs.isEmpty else { return }

        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            guard let target = try context.existingObject(with: pinboardID) as? Pinboard else {
                throw ClipItemStoreError.missingItem
            }

            for objectID in objectIDs {
                guard let item = try context.existingObject(with: objectID) as? ClipItem else {
                    continue
                }

                for pinboard in item.pinboards ?? []
                where !pinboard.isSystemMarten && pinboard.objectID != target.objectID {
                    item.removeFromPinboards(pinboard)
                }

                try validateMixedMembership(item: item, targetPinboard: target)
                item.addToPinboards(target)
            }

            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            for objectID in objectIDs {
                if let item = try? viewContext.existingObject(with: objectID) as? ClipItem {
                    viewContext.refresh(item, mergeChanges: true)
                }
            }
            if let pinboard = try? viewContext.existingObject(with: pinboardID) as? Pinboard {
                viewContext.refresh(pinboard, mergeChanges: true)
            }
        }
    }

    func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws {
        guard !orderedIDs.isEmpty else { return }

        let context = persistence.newBackgroundContext()

        try context.performAndWaitThrowing {
            for (index, objectID) in orderedIDs.enumerated() {
                guard let pinboard = try context.existingObject(with: objectID) as? Pinboard else {
                    continue
                }
                pinboard.sortOrder = Int16(index)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            for objectID in orderedIDs {
                if let pinboard = try? viewContext.existingObject(with: objectID) as? Pinboard {
                    viewContext.refresh(pinboard, mergeChanges: true)
                }
            }
        }
    }

    func fetchOrCreateSystemMartenPinboard(in context: NSManagedObjectContext) throws -> Pinboard {
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemMarten == YES")
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            return existing
        }

        guard
            let pinboard = NSEntityDescription.insertNewObject(
                forEntityName: "Pinboard",
                into: context
            ) as? Pinboard
        else {
            throw ClipItemStoreError.creationFailed
        }

        pinboard.id = UUID()
        pinboard.name = "Marten"
        pinboard.colorHex = "#808080"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = true
        pinboard.createdAt = Date()
        return pinboard
    }

    /// Validates that adding an item to a pinboard won't create mixed shared/non-shared membership.
    /// An item cannot belong to both a shared and a non-shared custom pinboard simultaneously.
    private func validateMixedMembership(item: ClipItem, targetPinboard: Pinboard) throws {
        let targetIsShared = targetPinboard.isShared
        guard let existingPinboards = item.pinboards else { return }

        for pinboard in existingPinboards where !pinboard.isSystemMarten {
            if pinboard.isShared != targetIsShared {
                throw PinboardSharingError.insufficientPermission
            }
        }
    }

    private func nextPinboardSortOrder(in context: NSManagedObjectContext) throws -> Int {
        let request = Pinboard.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1

        if let last = try context.fetch(request).first {
            return Int(last.sortOrder) + 1
        }

        return 0
    }
}

// SAFETY: PinboardRepository is immutable after initialization and performs all Core Data access
// via `performAndWaitThrowing` on the appropriate context queue.
extension PinboardRepository: @unchecked Sendable {}

extension PinboardRepository: PinboardRepositoryProtocol {}
