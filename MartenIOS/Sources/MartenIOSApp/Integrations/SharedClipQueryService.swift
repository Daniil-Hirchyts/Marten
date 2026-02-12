import Foundation
import MartenCore

public actor SharedClipQueryService {
    private let store: ClipItemStore
    private let searchService: (any SearchServicing)?

    public init(
        persistenceController: PersistenceController,
        store: ClipItemStore? = nil,
        searchService: (any SearchServicing)? = nil
    ) {
        self.store = store ?? ClipItemStore(persistence: persistenceController)
        self.searchService = searchService
    }

    public func recentItems(
        pinboardID: UUID? = nil,
        limit: Int = 25
    ) throws -> [SharedClipItemSummary] {
        let request = ClipItemSearchRequest(
            query: "",
            pinboardID: pinboardID,
            limit: max(1, limit)
        )
        let items: [ClipItem]
        if let searchService {
            items = try searchService.searchItems(request: request)
        } else {
            items = try store.searchItems(request: request)
        }
        return items.map(mapToSummary)
    }

    public func searchItems(
        query: String,
        pinboardID: UUID? = nil,
        limit: Int = 50
    ) throws -> [SharedClipItemSummary] {
        let request = ClipItemSearchRequest(
            query: query,
            pinboardID: pinboardID,
            limit: max(1, limit)
        )
        let items: [ClipItem]
        if let searchService {
            items = try searchService.searchItems(request: request)
        } else {
            items = try store.searchItems(request: request)
        }
        return items.map(mapToSummary)
    }

    public func pinboards() throws -> [SharedPinboardSummary] {
        let pinboards = try store.fetchPinboards()
        return pinboards
            .sorted { lhs, rhs in
                if lhs.isSystemMarten != rhs.isSystemMarten {
                    return lhs.isSystemMarten
                }
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map {
                SharedPinboardSummary(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    iconName: $0.iconName,
                    isSystemMarten: $0.isSystemMarten,
                    isShared: $0.isShared,
                    canMakeChanges: $0.canMakeChanges
                )
            }
    }

    private func mapToSummary(_ item: ClipItem) -> SharedClipItemSummary {
        let pinboardIDs = (item.pinboards ?? [])
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }

        return SharedClipItemSummary(
            id: item.id,
            createdAt: item.createdAt,
            itemType: item.itemTypeValue,
            primaryText: item.primaryText,
            plainText: item.plainTextContent,
            sourceAppName: item.sourceAppName,
            sourceAppBundleID: item.sourceAppBundleID,
            pinboardIDs: pinboardIDs
        )
    }
}
