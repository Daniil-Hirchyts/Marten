import CoreData
import Foundation

final class SearchService {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func searchItems(request searchRequest: ClipItemSearchRequest) throws -> [ClipItem] {
        let trimmedQuery = searchRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.isEmpty ? nil : trimmedQuery.normalizedForSearch()
        let fetchLimit = max(1, searchRequest.limit)

        let bgContext = persistence.newBackgroundContext()
        var fetchedIDs: [NSManagedObjectID] = []

        try bgContext.performAndWaitThrowing {
            let fetchRequest = ClipItem.fetchRequest()
            var predicates: [NSPredicate] = [NSPredicate(format: "isTransient == NO")]

            if let normalizedQuery {
                predicates.append(
                    NSPredicate(format: "searchableText CONTAINS[cd] %@", normalizedQuery)
                )
            }

            if let pinboardID = searchRequest.pinboardID {
                predicates.append(
                    NSPredicate(format: "ANY pinboards.id == %@", pinboardID as CVarArg)
                )
            }

            if let datePredicate = datePredicate(for: searchRequest.dateFilter) {
                predicates.append(datePredicate)
            }

            if !searchRequest.itemTypes.isEmpty {
                let rawValues = Array(Set(searchRequest.itemTypes.flatMap(rawItemTypeValues(for:))))
                predicates.append(NSPredicate(format: "itemType IN %@", rawValues))
            }

            if !searchRequest.sourceApps.isEmpty {
                let values = Array(searchRequest.sourceApps)
                predicates.append(
                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "sourceAppBundleID IN %@", values),
                        NSPredicate(format: "sourceAppName IN %@", values),
                    ])
                )
            }

            if let devicePredicate = sourceDevicePredicate(searchRequest.sourceDevices) {
                predicates.append(devicePredicate)
            }

            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            if searchRequest.pinboardID != nil {
                fetchRequest.sortDescriptors = [
                    NSSortDescriptor(key: "isPinned", ascending: false),
                    NSSortDescriptor(key: "displayOrder", ascending: false),
                    NSSortDescriptor(key: "modifiedAt", ascending: false),
                    NSSortDescriptor(key: "createdAt", ascending: false),
                ]
            } else {
                fetchRequest.sortDescriptors = [
                    NSSortDescriptor(key: "modifiedAt", ascending: false),
                    NSSortDescriptor(key: "createdAt", ascending: false),
                ]
            }
            fetchRequest.fetchLimit = fetchLimit
            fetchRequest.relationshipKeyPathsForPrefetching = []
            let items = try bgContext.fetch(fetchRequest)
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

    private func datePredicate(for filter: ClipItemDateFilter, now: Date = Date()) -> NSPredicate? {
        let calendar = Calendar.current
        switch filter {
        case .any:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            return NSPredicate(format: "createdAt >= %@", start as NSDate)
        case .yesterday:
            let startOfToday = calendar.startOfDay(for: now)
            guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            else {
                return nil
            }
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "createdAt >= %@", startOfYesterday as NSDate),
                NSPredicate(format: "createdAt < %@", startOfToday as NSDate),
            ])
        case .last7Days:
            guard let cutoff = calendar.date(byAdding: .day, value: -7, to: now) else {
                return nil
            }
            return NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
        case .last30Days:
            guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else {
                return nil
            }
            return NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
        }
    }

    private func sourceDevicePredicate(_ filters: Set<ClipItemSourceDevice>) -> NSPredicate? {
        guard !filters.isEmpty else { return nil }

        let thisDeviceMarkers = [
            "This Device",
            "local",
            "local device",
            "current device",
        ]
        let unknownMarkers = [
            "Unknown",
            "n/a",
            "na",
        ]

        let predicates: [NSPredicate] = filters.map { filter in
            switch filter {
            case .thisDevice:
                let markerPredicates = thisDeviceMarkers.map {
                    NSPredicate(format: "lastModifiedBy ==[c] %@", $0)
                }
                return NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                    NSPredicate(format: "lastModifiedBy == nil"),
                    NSPredicate(format: "lastModifiedBy == ''"),
                    ] + markerPredicates
                )
            case .unknown:
                let markerPredicates = unknownMarkers.map {
                    NSPredicate(format: "lastModifiedBy ==[c] %@", $0)
                }
                return NSCompoundPredicate(orPredicateWithSubpredicates: markerPredicates)
            case .named(let deviceName):
                return NSPredicate(format: "lastModifiedBy == %@", deviceName)
            }
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    private func rawItemTypeValues(for type: ItemType) -> [Int16] {
        if type == .text {
            return [ItemType.text.rawValue, ItemType.richText.rawValue]
        }
        return [type.rawValue]
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
