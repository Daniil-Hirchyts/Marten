#if canImport(AppIntents)
import AppIntents

struct MartenAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateMartenItemIntent(),
            phrases: [
                "Create item in \(.applicationName)",
                "Save to \(.applicationName)",
            ],
            shortTitle: "Create Item",
            systemImageName: "plus.square.on.square"
        )
        AppShortcut(
            intent: SearchMartenIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find in \(.applicationName)",
            ],
            shortTitle: "Search Marten",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetRecentMartenItemIntent(),
            phrases: [
                "Get recent item from \(.applicationName)",
                "Recent in \(.applicationName)",
            ],
            shortTitle: "Get Recent Item",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
#endif
