import Foundation
import MartenCore
import Observation

@MainActor
@Observable
final class MartenWatchBootstrap {
    let persistenceController: PersistenceController
    let container: MartenWatchContainer

    init(
        persistenceController: PersistenceController = .shared,
        container: MartenWatchContainer? = nil,
        userDefaults: UserDefaults = UserDefaults(suiteName: WatchDefaults.appGroupIdentifier) ?? .standard
    ) {
        self.persistenceController = persistenceController
        self.container = container ?? MartenWatchContainer(
            persistenceController: persistenceController,
            clipItemStore: ClipItemStore(persistence: persistenceController),
            userDefaults: userDefaults
        )
    }
}
