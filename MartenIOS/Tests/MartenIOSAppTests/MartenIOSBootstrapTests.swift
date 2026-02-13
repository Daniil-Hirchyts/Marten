import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class MartenIOSBootstrapTests: XCTestCase {
    func testBootstrapUsesInjectedPersistenceController() {
        let suiteName = "MartenIOSBootstrapTests"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let persistence = PersistenceController(inMemory: true)
        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )
        let bootstrap = MartenIOSBootstrap(persistenceController: persistence, container: container)

        XCTAssertTrue(bootstrap.persistenceController === persistence)
        XCTAssertTrue(bootstrap.container.persistenceController === persistence)
        XCTAssertTrue(bootstrap.container === container)
    }
}

private struct AlwaysDisabledSyncConfigurationProvider: MartenIOSSyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool {
        false
    }

    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool {
        false
    }
}
