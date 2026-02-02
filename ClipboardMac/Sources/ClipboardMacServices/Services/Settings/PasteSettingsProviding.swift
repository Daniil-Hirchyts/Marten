import Foundation

public protocol PasteSettingsProviding {
    var alwaysPastePlainText: Bool { get }
}

public struct UserDefaultsPasteSettingsProvider: PasteSettingsProviding {
    private enum Keys {
        static let alwaysPastePlainText = "alwaysPastePlainText"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var alwaysPastePlainText: Bool {
        userDefaults.bool(forKey: Keys.alwaysPastePlainText)
    }
}
