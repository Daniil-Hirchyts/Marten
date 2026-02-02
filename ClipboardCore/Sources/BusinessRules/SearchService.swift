import CoreData
import Foundation

final class SearchService {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func searchItems(query: String, limit: Int = 50, pinboardID: UUID? = nil) throws -> [ClipItem] {
        let normalized = query.normalizedForSearch()
        let context = persistence.viewContext
        var results: [ClipItem] = []

        try context.performAndWaitThrowing {
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
            request.relationshipKeyPathsForPrefetching = ["representations", "pinboards"]
            results = try context.fetch(request)
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

extension SearchService: @unchecked Sendable {}
