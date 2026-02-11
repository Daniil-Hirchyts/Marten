import Foundation

/// Feature flag controlling shared pinboards availability.
public enum SharedPinboardsFeatureFlag {
    public static let key = "sharedPinboardsEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
