import MartenCore
import CoreData
import Foundation
import OSLog

@MainActor
final class FirstLaunchContentSeeder {
    private static let onboardingCompletedKey = "hasCompletedOnboarding"

    private let clipItemStore: ClipItemStore
    private let userDefaults: UserDefaults

    init(clipItemStore: ClipItemStore, userDefaults: UserDefaults = .standard) {
        self.clipItemStore = clipItemStore
        self.userDefaults = userDefaults
    }

    func seedIfNeeded() {
        guard !userDefaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent) else { return }

        if userDefaults.bool(forKey: Self.onboardingCompletedKey) {
            markSeedingCompleted()
            return
        }

        let recoveringInterruptedSeed = userDefaults.bool(
            forKey: AppSettingsKeys.starterContentSeedInProgress)

        do {
            if !recoveringInterruptedSeed, try hasExistingUserData() {
                markSeedingCompleted()
                return
            }

            userDefaults.set(true, forKey: AppSettingsKeys.starterContentSeedInProgress)
            try seedStarterContent()
            markSeedingCompleted()
        } catch {
            Logger.app.error("Failed to seed starter content: \(error.localizedDescription)")
        }
    }

    private func markSeedingCompleted() {
        userDefaults.set(true, forKey: AppSettingsKeys.hasSeededStarterContent)
        userDefaults.set(false, forKey: AppSettingsKeys.starterContentSeedInProgress)
    }

    private func hasExistingUserData() throws -> Bool {
        if try !clipItemStore.fetchRecentItems(limit: 1).isEmpty {
            return true
        }

        let pinboards = try clipItemStore.fetchPinboards()
        return pinboards.contains { !$0.isSystemMarten }
    }

    private func seedStarterContent() throws {
        let starterPinboardNames = Set(Self.starterPinboards.map(\.name))
        var pinboardByName: [String: Pinboard] = [:]

        for pinboard in try clipItemStore.fetchPinboards()
        where starterPinboardNames.contains(pinboard.name) {
            pinboardByName[pinboard.name] = pinboard
        }

        for starterPinboard in Self.starterPinboards {
            let targetPinboard: Pinboard
            if let existing = pinboardByName[starterPinboard.name] {
                targetPinboard = existing
            } else {
                let created = try clipItemStore.createPinboard(
                    name: starterPinboard.name,
                    colorHex: starterPinboard.colorHex,
                    iconName: starterPinboard.iconName
                )
                pinboardByName[starterPinboard.name] = created
                targetPinboard = created
            }

            for card in starterPinboard.cards {
                try ensureStarterCardExists(
                    card,
                    in: targetPinboard
                )
            }
        }
    }

    private func ensureStarterCardExists(_ card: StarterCard, in pinboard: Pinboard) throws {
        let signature = card.signature

        if pinboard.items?.contains(where: { Self.matches($0, to: signature) }) == true {
            return
        }

        let reusableItem = try clipItemStore.fetchItems(
            primaryText: signature.primaryText,
            itemType: signature.itemType,
            limit: 20
        ).first(where: { candidate in
            let customPinboards = candidate.pinboards?.filter { !$0.isSystemMarten } ?? []
            return customPinboards.isEmpty
        })

        let item = try reusableItem ?? card.makeItem(in: clipItemStore)

        if item.pinboards?.contains(where: { $0.id == pinboard.id }) != true {
            try clipItemStore.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)
        }
    }

    private static func matches(_ item: ClipItem, to signature: StarterCardSignature) -> Bool {
        item.itemTypeValue == signature.itemType
            && item.primaryText == signature.primaryText
    }
}

private extension FirstLaunchContentSeeder {
    struct StarterCardSignature {
        let itemType: ItemType
        let primaryText: String
    }

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

        var signature: StarterCardSignature {
            switch self {
            case .text(let text):
                StarterCardSignature(itemType: .text, primaryText: text)
            case .code(let snippet):
                StarterCardSignature(itemType: .code, primaryText: snippet)
            case .url(let url):
                StarterCardSignature(itemType: .url, primaryText: url)
            }
        }

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
