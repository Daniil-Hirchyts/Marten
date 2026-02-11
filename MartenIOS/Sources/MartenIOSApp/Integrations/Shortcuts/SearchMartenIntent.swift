#if canImport(AppIntents)
import AppIntents
import MartenCore

struct SearchMartenIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Marten"
    static var description = IntentDescription("Search your Marten history.")

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let persistence: PersistenceController
        if let configured = try? MartenIOSStorageConfiguration().makePersistenceController() {
            persistence = configured
        } else {
            persistence = PersistenceController()
        }

        let service = SharedClipQueryService(persistenceController: persistence)
        let results = try await service.searchItems(query: query, limit: 5)
        guard let first = results.first else {
            return .result(dialog: "No matching items found.")
        }
        let text = first.insertionText.isEmpty ? "Untitled item" : first.insertionText
        return .result(dialog: "Top result: \(text)")
    }
}
#endif
