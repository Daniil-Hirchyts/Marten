import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class DeepLinkRoutingTests: XCTestCase {
    private let suiteName = "DeepLinkRoutingTests"
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

    func testPinboardDeepLinkSelectsPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Links", colorHex: "#2255AA")

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://pinboard/\(pinboard.id.uuidString)")!)

        XCTAssertEqual(container.selectedPinboardID, pinboard.id)
    }

    func testItemDeepLinkSelectsContainingPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Projects", colorHex: "#119944")
        let item = try store.createTextItem(text: "Open me", isUserCreated: true)
        try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://item/\(item.id.uuidString)")!)

        XCTAssertEqual(container.selectedPinboardID, pinboard.id)
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
