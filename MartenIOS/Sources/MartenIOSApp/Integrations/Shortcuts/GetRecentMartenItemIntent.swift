#if canImport(AppIntents)
import AppIntents
import MartenCore

struct GetRecentMartenItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recent Marten Item"
    static var description = IntentDescription("Fetch the most recent item from Marten.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let persistence: PersistenceController
        if let configured = try? MartenIOSStorageConfiguration().makePersistenceController() {
            persistence = configured
        } else {
            persistence = PersistenceController()
        }

        let service = SharedClipQueryService(persistenceController: persistence)
        let recent = try await service.recentItems(limit: 1)
        guard let item = recent.first else {
            return .result(dialog: "No items found in Marten.")
        }

        let text = item.insertionText.isEmpty ? "Untitled item" : item.insertionText
        return .result(dialog: "Most recent item: \(text)")
    }
}
#endif
