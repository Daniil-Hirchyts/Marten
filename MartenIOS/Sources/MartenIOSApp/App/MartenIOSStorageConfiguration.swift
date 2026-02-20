import Foundation
import MartenCore

public struct MartenIOSStorageConfiguration: Sendable {
    public static let defaultAppGroupIdentifier = "group.com.hirchyts.marten"

    public let sharedStorage: MartenSharedStorage

    public init(appGroupIdentifier: String = defaultAppGroupIdentifier) {
        self.sharedStorage = MartenSharedStorage(appGroupIdentifier: appGroupIdentifier)
    }

    @MainActor
    public func makeBootstrap(userDefaults: UserDefaults = .standard) -> MartenIOSBootstrap {
        guard
            let persistenceController = try? makePersistenceController(),
            let assetStore = try? makeAssetStore()
        else {
            return MartenIOSBootstrap()
        }

        // Point the shared singleton at the App Group container so that all components
        // (ImageThumbnailLoader, LinkPreviewImageLoader, SharedClipQueryService, …) read
        // from the same location that ClipItemStore writes to.
        AssetStore.shared = assetStore

        let clipItemStore = ClipItemStore(
            persistence: persistenceController,
            assetStore: assetStore
        )
        let container = MartenIOSAppContainer(
            persistenceController: persistenceController,
            clipItemStore: clipItemStore,
            userDefaults: userDefaults
        )

        return MartenIOSBootstrap(
            persistenceController: persistenceController,
            container: container
        )
    }

    public func makePersistenceController() throws -> PersistenceController {
        _ = try sharedStorage.migrateLegacyDataIfNeeded()
        let storeURL = try sharedStorage.sharedStoreURL()
        return PersistenceController(storeURL: storeURL)
    }

    public func makeAssetStore() throws -> AssetStore {
        let assetsURL = try sharedStorage.sharedAssetsDirectoryURL()
        return AssetStore(baseURL: assetsURL)
    }
}
