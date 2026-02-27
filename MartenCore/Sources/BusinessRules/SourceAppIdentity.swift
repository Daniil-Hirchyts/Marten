import Foundation

public enum SourceAppIdentity {
    public static let martenBundleID = "com.hirchyts.marten"
    public static let martenDisplayName = "Marten"

    public static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    public static func isMartenSource(bundleID: String?, appName: String?) -> Bool {
        if let bundleID = normalized(bundleID), isMartenBundleID(bundleID) {
            return true
        }
        if let appName = normalized(appName), appName == martenDisplayName.lowercased() {
            return true
        }
        return false
    }

    public static func isMartenBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID = normalized(bundleID) else { return false }
        return bundleID == martenBundleID || bundleID.hasPrefix(martenBundleID + ".")
    }

    public static func resolvedBundleID(bundleID: String?, appName: String?) -> String? {
        if let bundleID = normalized(bundleID) {
            return isMartenBundleID(bundleID) ? martenBundleID : bundleID
        }
        if isMartenSource(bundleID: nil, appName: appName) {
            return martenBundleID
        }
        return nil
    }
}
