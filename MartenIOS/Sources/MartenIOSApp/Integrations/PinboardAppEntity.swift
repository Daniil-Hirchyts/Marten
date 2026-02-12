#if canImport(AppIntents)
import AppIntents
import MartenCore

public struct PinboardAppEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pinboard"
    public static var defaultQuery = PinboardEntityQuery()

    public var id: String
    public var name: String
    public var colorHex: String
    public var iconName: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public init(id: String, name: String, colorHex: String, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
    }
}

public struct PinboardEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PinboardAppEntity] {
        let all = try await loadPinboards()
        return all.filter { identifiers.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [PinboardAppEntity] {
        try await loadPinboards()
    }

    private func loadPinboards() async throws -> [PinboardAppEntity] {
        let persistence: PersistenceController
        if let configured = try? MartenIOSStorageConfiguration().makePersistenceController() {
            persistence = configured
        } else {
            persistence = PersistenceController()
        }

        let queryService = SharedClipQueryService(persistenceController: persistence)
        let pinboards = try await queryService.pinboards()
        return pinboards
            .filter { !$0.isSystemMarten }
            .map {
                PinboardAppEntity(
                    id: $0.id.uuidString,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    iconName: $0.iconName
                )
            }
    }
}
#endif
