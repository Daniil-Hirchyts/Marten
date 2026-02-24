import CoreData
import Foundation
import MartenCore

struct SystemPinboardBootstrapper {
    /// Ensures exactly one system pinboard exists in the given context.
    ///
    /// - Returns: A tuple of `(survivingID, removedIDs)` to reconcile selection state.
    func ensureSystemPinboard(in context: NSManagedObjectContext) throws -> (UUID?, Set<UUID>) {
        var survivingID: UUID?
        var removedIDs = Set<UUID>()

        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == YES")

            let systemPinboards = try context.fetch(request)

            if systemPinboards.isEmpty {
                guard
                    let pinboard = NSEntityDescription.insertNewObject(
                        forEntityName: "Pinboard",
                        into: context
                    ) as? Pinboard
                else {
                    return
                }

                pinboard.id = UUID()
                pinboard.name = "Marten"
                pinboard.colorHex = "#808080"
                pinboard.sortOrder = 0
                pinboard.isSystemMarten = true
                pinboard.createdAt = Date()
                survivingID = pinboard.id

                try context.save()
                return
            }

            let sortedPinboards = systemPinboards.sorted { lhs, rhs in
                let lhsItemCount = lhs.items?.count ?? 0
                let rhsItemCount = rhs.items?.count ?? 0
                if lhsItemCount != rhsItemCount {
                    return lhsItemCount > rhsItemCount
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            guard let canonical = sortedPinboards.first else { return }
            survivingID = canonical.id

            canonical.name = "Marten"
            canonical.colorHex = "#808080"
            canonical.sortOrder = 0
            canonical.isSystemMarten = true

            for duplicate in sortedPinboards.dropFirst() {
                removedIDs.insert(duplicate.id)

                if let items = duplicate.items {
                    for item in items where !(canonical.items?.contains(item) ?? false) {
                        canonical.addToItems(item)
                    }
                }

                context.delete(duplicate)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        return (survivingID, removedIDs)
    }
}
