#if canImport(AppIntents)
import AppIntents
import MartenCore

struct CreateMartenItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Marten Item"
    static var description = IntentDescription("Create a new text item in Marten.")

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let persistence: PersistenceController
        if let configured = try? MartenIOSStorageConfiguration().makePersistenceController() {
            persistence = configured
        } else {
            persistence = PersistenceController()
        }

        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(
            text: text,
            sourceApp: SourceAppInfo(bundleID: "com.apple.shortcuts", name: "Shortcuts"),
            isUserCreated: true
        )

        return .result(dialog: "Saved to Marten.")
    }
}
#endif
