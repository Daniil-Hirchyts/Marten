import Foundation

public protocol ScreenSharingSettingsProviding {
    func showDuringScreenSharing() -> Bool
    func setShowDuringScreenSharing(_ value: Bool)
}

public struct UserDefaultsScreenSharingSettingsProvider: ScreenSharingSettingsProviding {
    private enum Keys {
        static let showDuringScreenSharing = "showDuringScreenSharing"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func showDuringScreenSharing() -> Bool {
        guard userDefaults.object(forKey: Keys.showDuringScreenSharing) != nil else {
            return true
        }
        return userDefaults.bool(forKey: Keys.showDuringScreenSharing)
    }

    public func setShowDuringScreenSharing(_ value: Bool) {
        userDefaults.set(value, forKey: Keys.showDuringScreenSharing)
    }
}
