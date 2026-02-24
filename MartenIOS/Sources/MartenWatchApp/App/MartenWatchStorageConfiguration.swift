import Foundation
import MartenCore

struct MartenWatchStorageConfiguration: Sendable {
    static let defaultAppGroupIdentifier = WatchDefaults.appGroupIdentifier

    let sharedStorage: MartenSharedStorage

    init(appGroupIdentifier: String = defaultAppGroupIdentifier) {
        self.sharedStorage = MartenSharedStorage(appGroupIdentifier: appGroupIdentifier)
    }

    @MainActor
    func makeBootstrap(
        userDefaults: UserDefaults = UserDefaults(suiteName: defaultAppGroupIdentifier) ?? .standard
    ) -> MartenWatchBootstrap {
        guard
            let persistenceController = try? makePersistenceController(),
            let assetStore = try? makeAssetStore()
        else {
            return MartenWatchBootstrap(userDefaults: userDefaults)
        }

        AssetStore.shared = assetStore

        let clipItemStore = ClipItemStore(
            persistence: persistenceController,
            assetStore: assetStore
        )
        let container = MartenWatchContainer(
            persistenceController: persistenceController,
            clipItemStore: clipItemStore,
            userDefaults: userDefaults
        )

        return MartenWatchBootstrap(
            persistenceController: persistenceController,
            container: container
        )
    }

    func makePersistenceController() throws -> PersistenceController {
        _ = try sharedStorage.migrateLegacyDataIfNeeded()
        let storeURL = try sharedStorage.sharedStoreURL()
        return PersistenceController(storeURL: storeURL)
    }

    func makeAssetStore() throws -> AssetStore {
        let assetsURL = try sharedStorage.sharedAssetsDirectoryURL()
        return AssetStore(baseURL: assetsURL)
    }
}
