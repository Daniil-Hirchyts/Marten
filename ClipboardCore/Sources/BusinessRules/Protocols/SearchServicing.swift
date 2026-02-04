import Foundation

public protocol SearchServicing: Sendable {
    func searchItems(query: String, limit: Int, pinboardID: UUID?) throws -> [ClipItem]
    func deriveSearchableText(primaryText: String?, representations: [ClipRepresentationPayload])
        -> String?
}

public extension SearchServicing {
    func searchItems(query: String, limit: Int = 50) throws -> [ClipItem] {
        try searchItems(query: query, limit: limit, pinboardID: nil)
    }
}
