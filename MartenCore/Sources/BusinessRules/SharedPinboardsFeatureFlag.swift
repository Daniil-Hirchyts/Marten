import Foundation

/// Feature flag controlling shared pinboards availability.
public enum SharedPinboardsFeatureFlag {
    public static let key = "sharedPinboardsEnabled"
    public static let defaultValue = true

    public static var isEnabled: Bool {
        let defaults = UserDefaults(suiteName: "group.com.hirchyts.marten") ?? .standard
        return isEnabled(in: defaults)
    }

    public static func isEnabled(in userDefaults: UserDefaults) -> Bool {
        let value = userDefaults.object(forKey: key) as? Bool
        return value ?? defaultValue
    }

    public static func registerDefaults(_ userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [key: defaultValue])
    }
}
