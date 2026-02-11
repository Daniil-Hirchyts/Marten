import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class AppContainerSyncIntegrationTests: XCTestCase {
    private let suiteName = "AppContainerSyncIntegrationTests"
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testTriggerSyncNowIsNoOpWhenSyncUnavailable() async {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: DisabledSyncProvider()
        )

        // syncCoordinator is nil, so triggerSyncNow should be a no-op
        await container.triggerSyncNow()

        XCTAssertFalse(container.isRunningSyncAction)
        XCTAssertNil(container.syncErrorMessage)
    }

    func testSyncErrorMessageIsNilInitially() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: DisabledSyncProvider()
        )

        XCTAssertNil(container.syncErrorMessage)
    }

    func testClearSyncErrorResetsMessage() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: DisabledSyncProvider()
        )

        container.syncErrorMessage = "Test error"
        XCTAssertNotNil(container.syncErrorMessage)

        container.clearSyncError()
        XCTAssertNil(container.syncErrorMessage)
    }
}

private struct DisabledSyncProvider: MartenIOSSyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool { false }
    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool { false }
}
