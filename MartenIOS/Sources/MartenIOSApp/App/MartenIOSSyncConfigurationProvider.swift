import Foundation
#if canImport(Security) && !os(iOS)
import Security
#endif

protocol MartenIOSSyncConfigurationProviding: Sendable {
    func canUseCloudKit(containerIdentifier: String) -> Bool
    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool
}

struct MartenIOSSyncConfigurationProvider: MartenIOSSyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool {
        return true
    }

    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: MartenIOSDefaults.syncEnabledKey)
    }
}
