import Foundation
import MartenCore

actor WatchQueryService {
    private let store: ClipItemStore

    init(store: ClipItemStore) {
        self.store = store
    }

    func pinboards() throws -> [WatchPinboardSummary] {
        try store.fetchPinboards()
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
                WatchPinboardSummary(
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

    func items(
        query: String,
        pinboardID: UUID?,
        limit: Int = 100
    ) throws -> [WatchClipSummary] {
        let request = ClipItemSearchRequest(
            query: query,
            pinboardID: pinboardID,
            limit: max(1, limit)
        )

        return try store.searchItems(request: request)
            .map {
                WatchClipSummary(
                    id: $0.id,
                    createdAt: $0.createdAt,
                    modifiedAt: $0.modifiedAt,
                    itemType: $0.itemTypeValue,
                    primaryText: $0.primaryText,
                    plainText: $0.plainTextContent,
                    sourceAppName: $0.sourceAppName,
                    pinboardIDs: ($0.pinboards ?? []).map(\.id),
                    isPinned: $0.isPinned,
                    byteCount: $0.byteCount,
                    thumbnailPath: $0.thumbnailPath
                )
            }
    }
}
