import Foundation
import Observation

@MainActor
@Observable
final class IntegrationsStatusModel {
    private let appGroupIdentifier: String
    private let userDefaults: UserDefaults

    private(set) var keyboardLastSeenAt: Date?
    private(set) var shareExtensionLastSuccessAt: Date?

    init(
        appGroupIdentifier: String = MartenIOSStorageConfiguration.defaultAppGroupIdentifier,
        userDefaults: UserDefaults = .standard
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.userDefaults = userDefaults
        refresh()
    }

    var keyboardLikelyEnabled: Bool {
        guard let keyboardLastSeenAt else { return false }
        return keyboardLastSeenAt > Date().addingTimeInterval(-60 * 60 * 24 * 30)
    }

    var shareExtensionRecentlyUsed: Bool {
        guard let shareExtensionLastSuccessAt else { return false }
        return shareExtensionLastSuccessAt > Date().addingTimeInterval(-60 * 60 * 24 * 30)
    }

    func refresh() {
        let groupDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? userDefaults

        let keyboardTimestamp = groupDefaults.double(forKey: MartenIOSDefaults.keyboardLastSeenAtKey)
        keyboardLastSeenAt = keyboardTimestamp > 0 ? Date(timeIntervalSince1970: keyboardTimestamp) : nil

        let shareTimestamp = groupDefaults.double(forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey)
        shareExtensionLastSuccessAt = shareTimestamp > 0 ? Date(timeIntervalSince1970: shareTimestamp) : nil
    }
}
