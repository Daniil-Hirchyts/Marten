import ClipboardCore
import CoreData
import Foundation
import OSLog

@MainActor
final class FirstLaunchContentSeeder {
    private let clipItemStore: ClipItemStore
    private let userDefaults: UserDefaults

    init(clipItemStore: ClipItemStore, userDefaults: UserDefaults = .standard) {
        self.clipItemStore = clipItemStore
        self.userDefaults = userDefaults
    }

    func seedIfNeeded() {
        guard !userDefaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent) else { return }

        if userDefaults.bool(forKey: "hasCompletedOnboarding") {
            userDefaults.set(true, forKey: AppSettingsKeys.hasSeededStarterContent)
            return
        }

        do {
            if try hasExistingUserData() {
                userDefaults.set(true, forKey: AppSettingsKeys.hasSeededStarterContent)
                return
            }

            try seedStarterContent()
            userDefaults.set(true, forKey: AppSettingsKeys.hasSeededStarterContent)
        } catch {
            Logger.app.error("Failed to seed starter content: \(error.localizedDescription)")
        }
    }

    private func hasExistingUserData() throws -> Bool {
        if try !clipItemStore.fetchRecentItems(limit: 1).isEmpty {
            return true
        }

        let pinboards = try clipItemStore.fetchPinboards()
        return pinboards.contains { !$0.isSystemClipboard }
    }

    private func seedStarterContent() throws {
        var itemAssignments: [(objectID: NSManagedObjectID, pinboardName: String)] = []

        for starterPinboard in Self.starterPinboards {
            for card in starterPinboard.cards {
                let item = try card.makeItem(in: clipItemStore)
                itemAssignments.append(
                    (objectID: item.objectID, pinboardName: starterPinboard.name)
                )
            }
        }

        var pinboardByName: [String: Pinboard] = [:]
        for starterPinboard in Self.starterPinboards {
            let pinboard = try clipItemStore.createPinboard(
                name: starterPinboard.name,
                colorHex: starterPinboard.colorHex,
                iconName: starterPinboard.iconName
            )
            pinboardByName[starterPinboard.name] = pinboard
        }

        for assignment in itemAssignments {
            guard let pinboard = pinboardByName[assignment.pinboardName] else { continue }
            try clipItemStore.moveItem(objectID: assignment.objectID, toPinboard: pinboard.objectID)
        }
    }
}

private extension FirstLaunchContentSeeder {
    struct StarterPinboard {
        let name: String
        let colorHex: String
        let iconName: String
        let cards: [StarterCard]
    }

    enum StarterCard {
        case text(String)
        case code(String)
        case url(String)

        func makeItem(in store: ClipItemStore) throws -> ClipItem {
            switch self {
            case .text(let text):
                return try store.createTextItem(text: text)
            case .code(let snippet):
                return try store.createItem(
                    payload: ClipItemPayload(
                        representations: [.plainText(snippet)],
                        primaryText: snippet,
                        itemType: .code
                    )
                )
            case .url(let url):
                return try store.createItem(
                    payload: ClipItemPayload(
                        representations: [.plainText(url)],
                        primaryText: url,
                        itemType: .url,
                        needsLinkPreview: true
                    )
                )
            }
        }
    }

    static let starterPinboards: [StarterPinboard] = [
        StarterPinboard(
            name: "Work",
            colorHex: "#3A86FF",
            iconName: "briefcase.fill",
            cards: [
                .text(
                    """
                    Sprint checklist:
                    - Review pull requests
                    - Publish release notes
                    - Send status update
                    """
                ),
                .code(
                    """
                    git switch -c feature/quick-fix
                    swift test --filter PinboardTests
                    git push origin HEAD
                    """
                ),
            ]
        ),
        StarterPinboard(
            name: "Learning",
            colorHex: "#FF9F1C",
            iconName: "graduationcap.fill",
            cards: [
                .url("https://developer.apple.com/documentation/swiftui"),
                .text(
                    """
                    Keyboard shortcuts to try:
                    - Open overlay: Control + Option + Space
                    - Search instantly: start typing
                    - Paste selection: Return
                    """
                ),
            ]
        ),
        StarterPinboard(
            name: "Personal",
            colorHex: "#2A9D8F",
            iconName: "house.fill",
            cards: [
                .text(
                    """
                    Weekend plan:
                    - Hike at 9:00
                    - Buy groceries
                    - Call family
                    """
                ),
                .url("https://maps.apple.com/?q=Coffee"),
            ]
        ),
    ]
}
