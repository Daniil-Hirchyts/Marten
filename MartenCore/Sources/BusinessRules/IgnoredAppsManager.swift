import AppKit
import Foundation

public struct IgnoredApp: Codable, Identifiable, Equatable {
    public let bundleIdentifier: String
    public let name: String
    public let iconData: Data?
    public let addedAt: Date

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, name: String, iconData: Data? = nil, addedAt: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.iconData = iconData
        self.addedAt = addedAt
    }
}

public final class IgnoredAppsManager {
    private let userDefaultsKey = "ignoredApps"
    private let userDefaults: UserDefaults

    public private(set) var ignoredApps: [IgnoredApp]

    public init(userDefaults: UserDefaults? = nil) {
        self.userDefaults = userDefaults ?? .standard
        self.ignoredApps = []

        let loaded = load()
        if loaded.isEmpty {
            self.ignoredApps = Self.defaultIgnoredApps
            save()
        } else {
            self.ignoredApps = loaded
        }
    }

    public func add(_ app: IgnoredApp) {
        guard !contains(bundleIdentifier: app.bundleIdentifier) else {
            return
        }

        ignoredApps.append(app)
        save()
    }

    public func remove(bundleIdentifier: String) {
        let originalCount = ignoredApps.count
        ignoredApps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        if ignoredApps.count != originalCount {
            save()
        }
    }

    public func isIgnored(bundleIdentifier: String) -> Bool {
        contains(bundleIdentifier: bundleIdentifier)
    }

    public func contains(bundleIdentifier: String) -> Bool {
        ignoredApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Filters out apps that are not installed on the system.
    ///
    /// This method checks each ignored app's bundle identifier and removes it
    /// if the app cannot be found on the system via NSWorkspace.
    public func filterInstalledApps() {
        let originalCount = ignoredApps.count
        ignoredApps.removeAll { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) == nil
        }
        
        if ignoredApps.count != originalCount {
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(ignoredApps)
            userDefaults.set(data, forKey: userDefaultsKey)
        } catch {
            userDefaults.removeObject(forKey: userDefaultsKey)
        }
    }

    private func load() -> [IgnoredApp] {
        guard let data = userDefaults.data(forKey: userDefaultsKey) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([IgnoredApp].self, from: data)) ?? []
    }

    public static var defaultIgnoredApps: [IgnoredApp] {
        let defaultDate = Date(timeIntervalSince1970: 0)
        return [
            IgnoredApp(bundleIdentifier: "com.apple.keychainaccess", name: "Keychain Access", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.apple.Passwords", name: "Passwords", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.1password.1password", name: "1Password", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.agilebits.onepassword7", name: "1Password 7", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.lastpass.LastPass", name: "LastPass", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.dashlane.dashlanephonefinal", name: "Dashlane", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.bitwarden.desktop", name: "Bitwarden", addedAt: defaultDate),
            IgnoredApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Bitwarden", addedAt: defaultDate)
        ]
    }
}
