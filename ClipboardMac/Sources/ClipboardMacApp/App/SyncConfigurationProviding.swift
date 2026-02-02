import Foundation
import Security

protocol SyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool
    func isSyncEnabled() -> Bool
}

struct DefaultSyncConfigurationProvider: SyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let servicesKey = "com.apple.developer.icloud-services" as CFString
        let containersKey = "com.apple.developer.icloud-container-identifiers" as CFString
        let servicesValue = SecTaskCopyValueForEntitlement(task, servicesKey, nil)
        let containersValue = SecTaskCopyValueForEntitlement(task, containersKey, nil)

        let services =
            servicesValue as? [String]
            ?? (servicesValue as? String).map { [$0] }
            ?? []
        let containers =
            containersValue as? [String]
            ?? (containersValue as? String).map { [$0] }
            ?? []

        return services.contains("CloudKit") && containers.contains(containerIdentifier)
    }

    func isSyncEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "com.paste.syncEnabled")
    }
}
