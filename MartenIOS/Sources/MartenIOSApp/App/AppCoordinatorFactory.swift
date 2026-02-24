import CloudKit
import CoreData
import Foundation
import MartenCore

@MainActor
enum AppCoordinatorFactory {
    static func makeSyncCoordinator(
        persistenceController: PersistenceController,
        userDefaults: UserDefaults,
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding
    ) -> SyncCoordinator? {
        let cloudKitConfiguration = CloudKitConfiguration.default

        guard
            syncConfigurationProvider.canUseCloudKit(
                containerIdentifier: cloudKitConfiguration.containerIdentifier
            )
        else {
            return nil
        }

        let syncCoordinator = SyncCoordinator.create(
            cloudKitConfiguration: cloudKitConfiguration,
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncEnabledProvider: {
                UserDefaults.standard.bool(forKey: MartenIOSDefaults.syncEnabledKey)
            }
        )

        syncCoordinator.syncEnabled = syncConfigurationProvider.isSyncEnabled(userDefaults)

        return syncCoordinator
    }

    static func makeSharingRepository(
        persistenceController: PersistenceController,
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding,
        isPinboardLocked: (@MainActor @Sendable (UUID) -> Bool)? = nil
    ) -> (any PinboardSharingRepositoryProtocol)? {
        guard SharedPinboardsFeatureFlag.isEnabled else {
            return nil
        }

        let cloudKitConfiguration = CloudKitConfiguration.default
        guard
            syncConfigurationProvider.canUseCloudKit(
                containerIdentifier: cloudKitConfiguration.containerIdentifier)
        else {
            return nil
        }

        let zoneID = CKRecordZone.ID(
            zoneName: cloudKitConfiguration.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let cloudKitManager = CloudKitManager(configuration: cloudKitConfiguration)
        let recordMapper = CloudRecordMapper(zoneID: zoneID)
        let shareCoordinator = ShareCoordinator(
            cloudKitManager: cloudKitManager,
            persistenceController: persistenceController,
            recordMapper: recordMapper
        )
        return PinboardSharingRepository(
            shareCoordinator: shareCoordinator,
            persistenceController: persistenceController,
            isPinboardLocked: isPinboardLocked
        )
    }
}
