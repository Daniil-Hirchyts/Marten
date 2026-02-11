import MartenCore

public protocol ClipItemQuerying: Sendable {
    func search(request: ClipItemSearchRequest) async throws -> [ClipItem]
}

public actor ClipItemQueryService {
    private let store: ClipItemStore

    public init(store: ClipItemStore) {
        self.store = store
    }
}

extension ClipItemQueryService: ClipItemQuerying {
    public func search(request: ClipItemSearchRequest) async throws -> [ClipItem] {
        try store.searchItems(request: request)
    }
}
