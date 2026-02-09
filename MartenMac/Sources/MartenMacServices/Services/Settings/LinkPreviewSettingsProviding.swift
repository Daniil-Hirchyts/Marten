import Foundation

public protocol LinkPreviewSettingsProviding {
    var isLinkPreviewEnabled: Bool { get }
}

public struct UserDefaultsLinkPreviewSettingsProvider: LinkPreviewSettingsProviding {
    private enum Keys {
        static let generateLinkPreviews = "generateLinkPreviews"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var isLinkPreviewEnabled: Bool {
        userDefaults.bool(forKey: Keys.generateLinkPreviews)
    }
}
