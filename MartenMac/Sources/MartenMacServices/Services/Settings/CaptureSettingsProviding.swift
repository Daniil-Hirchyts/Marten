import Foundation

public protocol CaptureSettingsProviding {
    var ignoreConfidentialContent: Bool { get }
    var ignoreTransientContent: Bool { get }
}

public struct UserDefaultsCaptureSettingsProvider: CaptureSettingsProviding {
    private enum Keys {
        static let ignoreConfidentialContent = "ignoreConfidentialContent"
        static let ignoreTransientContent = "ignoreTransientContent"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var ignoreConfidentialContent: Bool {
        value(forKey: Keys.ignoreConfidentialContent, default: true)
    }

    public var ignoreTransientContent: Bool {
        value(forKey: Keys.ignoreTransientContent, default: true)
    }

    private func value(forKey key: String, default defaultValue: Bool) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key)
    }
}
