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
        #if targetEnvironment(simulator)
        return true
        #else
        #if canImport(Security) && !os(iOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }

        let servicesKey = "com.apple.developer.icloud-services" as CFString
        let containersKey = "com.apple.developer.icloud-container-identifiers" as CFString

        let servicesValue = SecTaskCopyValueForEntitlement(task, servicesKey, nil)
        let containersValue = SecTaskCopyValueForEntitlement(task, containersKey, nil)

        let services = (
            servicesValue as? [String]
            ?? (servicesValue as? String).map { [$0] }
            ?? []
        )

        let containers = (
            containersValue as? [String]
            ?? (containersValue as? String).map { [$0] }
            ?? []
        )

        return services.contains("CloudKit") && containers.contains(containerIdentifier)
        #else
        let services = provisioningEntitlementValues(for: "com.apple.developer.icloud-services")
        let containers = provisioningEntitlementValues(for: "com.apple.developer.icloud-container-identifiers")

        return services.contains("CloudKit") && containers.contains(containerIdentifier)
        #endif
        #endif
    }

    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: MartenIOSDefaults.syncEnabledKey)
    }

    private func provisioningEntitlementValues(for key: String) -> [String] {
        guard
            let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: profileURL),
            let text = String(data: data, encoding: .ascii),
            let plistStart = text.range(of: "<plist"),
            let plistEnd = text.range(of: "</plist>")
        else {
            return []
        }

        let plistString = String(text[plistStart.lowerBound..<plistEnd.upperBound])
        guard
            let plistData = plistString.data(using: .utf8),
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any]
        else {
            return []
        }

        if let values = entitlements[key] as? [String] {
            return values
        }

        if let value = entitlements[key] as? String {
            return [value]
        }

        return []
    }
}
