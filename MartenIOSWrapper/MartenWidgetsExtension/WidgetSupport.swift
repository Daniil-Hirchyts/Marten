import MartenCore
import MartenIOSApp
import WidgetKit

enum WidgetSupport {
    static func makePersistenceController() -> PersistenceController {
        if let controller = try? MartenIOSStorageConfiguration().makePersistenceController() {
            return controller
        }
        return PersistenceController()
    }

    static func placeholderEntries() -> [WidgetClipEntry] {
        [
            WidgetClipEntry(
                id: UUID(),
                title: "Welcome to Marten",
                subtitle: "Clipboard History",
                createdAt: Date(),
                deepLinkURL: URL(string: "marten://pinboard")!
            )
        ]
    }

    static func defaultReloadDate() -> Date {
        Date().addingTimeInterval(15 * 60)
    }
}
