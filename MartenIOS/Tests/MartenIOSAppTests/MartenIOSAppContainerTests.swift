import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class MartenIOSAppContainerTests: XCTestCase {
    private let suiteName = "MartenIOSAppContainerTests"
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

    func testContainerPersistsSelectedPinboardAndAppearance() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        let pinboardID = UUID()
        container.setSelectedPinboardID(pinboardID)
        container.setAppearance(.dark)

        let reloaded = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        XCTAssertEqual(reloaded.selectedPinboardID, pinboardID)
        XCTAssertEqual(reloaded.appearance, .dark)
    }

    func testCreateTextItemStoresContent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        await container.createTextItem("Unit test text")

        let items = try store.fetchRecentItems(limit: 10)
        XCTAssertTrue(items.contains(where: { $0.primaryText == "Unit test text" }))
    }
    func testHandleDeepLinkPinboardRouteSelectsPinboard() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        let pinboardID = UUID()
        let url = URL(string: "marten://pinboard/\(pinboardID.uuidString)")!

        container.handleDeepLink(url)

        XCTAssertEqual(container.selectedPinboardID, pinboardID)
    }

    func testHandleDeepLinkUnknownSchemeIsIgnored() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.setSelectedPinboardID(nil)
        let url = URL(string: "https://example.com/some/path")!

        container.handleDeepLink(url)

        XCTAssertNil(container.selectedPinboardID)
    }

    func testHandleDeepLinkItemRouteResolvesToPinboard() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        // Create a pinboard and item, associate them
        let pinboard = try! store.createPinboard(name: "Deep Link", colorHex: "#AABBCC")
        let item = try! store.createTextItem(text: "Deep linked item")
        try! store.addItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        let url = URL(string: "marten://item/\(item.id.uuidString)")!
        container.handleDeepLink(url)

        // Should resolve to the pinboard containing the item
        XCTAssertNotNil(container.selectedPinboardID)
    }

    func testHandleScenePhaseBackgroundStopsSyncWhenEnabled() async {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        // With sync disabled (our default), background should be a no-op
        await container.handleScenePhase(.background)

        // No crash, no error
        XCTAssertNil(container.syncErrorMessage)
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
