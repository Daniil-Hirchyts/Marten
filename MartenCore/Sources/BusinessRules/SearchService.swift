import CoreData
import Foundation

final class SearchService {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws -> [ClipItem] {
        let normalized = query.normalizedForSearch()

        let bgContext = persistence.newBackgroundContext()
        var fetchedIDs: [NSManagedObjectID] = []

        try bgContext.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "searchableText CONTAINS[cd] %@", normalized)
            ]

            if let pinboardID {
                predicates.append(
                    NSPredicate(format: "ANY pinboards.id == %@", pinboardID as CVarArg)
                )
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: "displayOrder", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            request.fetchLimit = limit
            request.relationshipKeyPathsForPrefetching = []
            let items = try bgContext.fetch(request)
            fetchedIDs = items.map { $0.objectID }
        }

        let viewContext = persistence.viewContext
        var results: [ClipItem] = []

        try viewContext.performAndWaitThrowing {
            results = try fetchedIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? ClipItem
            }
        }

        return results
    }

    func deriveSearchableText(
        primaryText: String?,
        representations: [ClipRepresentationPayload]
    ) -> String? {
        if let primaryText, !primaryText.isEmpty {
            return primaryText.normalizedForSearch()
        }

        let fallback = representations.compactMap(\.text).first
        return fallback?.normalizedForSearch()
    }
}

// SAFETY: SearchService is immutable after initialization. Core Data access is performed via
// `performAndWaitThrowing` on the appropriate context queue.
extension SearchService: @unchecked Sendable {}

extension SearchService: SearchServicing {}
