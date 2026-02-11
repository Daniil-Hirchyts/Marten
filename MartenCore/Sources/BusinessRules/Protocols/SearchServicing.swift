import Foundation

public enum ClipItemDateFilter: String, CaseIterable, Sendable {
    case any
    case today
    case yesterday
    case last7Days
    case last30Days
}

public enum ClipItemSourceDevice: Hashable, Sendable {
    case thisDevice
    case unknown
    case named(String)
}

public struct ClipItemSearchRequest: Sendable {
    public var query: String
    public var pinboardID: UUID?
    public var dateFilter: ClipItemDateFilter
    public var itemTypes: Set<ItemType>
    public var sourceApps: Set<String>
    public var sourceDevices: Set<ClipItemSourceDevice>
    public var limit: Int

    public init(
        query: String = "",
        pinboardID: UUID? = nil,
        dateFilter: ClipItemDateFilter = .any,
        itemTypes: Set<ItemType> = [],
        sourceApps: Set<String> = [],
        sourceDevices: Set<ClipItemSourceDevice> = [],
        limit: Int = 50
    ) {
        self.query = query
        self.pinboardID = pinboardID
        self.dateFilter = dateFilter
        self.itemTypes = itemTypes
        self.sourceApps = sourceApps
        self.sourceDevices = sourceDevices
        self.limit = max(1, limit)
    }
}

public protocol SearchServicing: Sendable {
    func searchItems(request: ClipItemSearchRequest) throws -> [ClipItem]
    func deriveSearchableText(primaryText: String?, representations: [ClipRepresentationPayload])
        -> String?
}

public extension SearchServicing {
    func searchItems(query: String, limit: Int, pinboardID: UUID?) throws -> [ClipItem] {
        try searchItems(
            request: ClipItemSearchRequest(
                query: query,
                pinboardID: pinboardID,
                limit: limit
            )
        )
    }

    func searchItems(query: String, limit: Int = 50) throws -> [ClipItem] {
        try searchItems(query: query, limit: limit, pinboardID: nil)
    }
}
