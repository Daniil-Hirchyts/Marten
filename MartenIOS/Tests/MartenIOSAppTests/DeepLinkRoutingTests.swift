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

    func testSearchDeepLinkSetsSearchTab() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://search")!)

        XCTAssertEqual(container.selectedTab, .search)
        XCTAssertEqual(container.pendingWidgetAction, .search)
    }

    func testPasteDeepLinkSetsPasteAction() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://paste")!)

        XCTAssertEqual(container.selectedTab, .dashboard)
        XCTAssertEqual(container.pendingWidgetAction, .paste)
    }

    func testCreateDeepLinkSetsCreateAction() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://create")!)

        XCTAssertEqual(container.selectedTab, .dashboard)
        XCTAssertEqual(container.pendingWidgetAction, .create)
    }
}

// MARK: - AppDeepLinkHandler unit tests (pure, no container needed)

final class AppDeepLinkHandlerTests: XCTestCase {
    private let handler = AppDeepLinkHandler()

    func testPinboardRoute() {
        let uuid = UUID()
        let action = handler.action(for: URL(string: "marten://pinboard/\(uuid.uuidString)")!)
        if case .selectPinboard(let id) = action {
            XCTAssertEqual(id, uuid)
        } else {
            XCTFail("Expected .selectPinboard, got \(String(describing: action))")
        }
    }

    func testItemRoute() {
        let uuid = UUID()
        let action = handler.action(for: URL(string: "marten://item/\(uuid.uuidString)")!)
        if case .selectItem(let id) = action {
            XCTAssertEqual(id, uuid)
        } else {
            XCTFail("Expected .selectItem, got \(String(describing: action))")
        }
    }

    func testSearchRoute() {
        let action = handler.action(for: URL(string: "marten://search")!)
        XCTAssertEqual(action, .search)
    }

    func testPasteRoute() {
        let action = handler.action(for: URL(string: "marten://paste")!)
        XCTAssertEqual(action, .paste)
    }

    func testCreateRoute() {
        let action = handler.action(for: URL(string: "marten://create")!)
        XCTAssertEqual(action, .create)
    }

    func testOpenRoute() {
        let action = handler.action(for: URL(string: "marten://open")!)
        XCTAssertEqual(action, .openDashboard)
    }

    func testUnknownSchemeReturnsNil() {
        let action = handler.action(for: URL(string: "https://example.com")!)
        XCTAssertNil(action)
    }

    func testUnknownRouteReturnsNil() {
        let action = handler.action(for: URL(string: "marten://unknown")!)
        XCTAssertNil(action)
    }

    func testPinboardRouteWithInvalidUUIDReturnsNil() {
        let action = handler.action(for: URL(string: "marten://pinboard/not-a-uuid")!)
        XCTAssertNil(action)
    }

    func testItemRouteWithMissingIDReturnsNil() {
        let action = handler.action(for: URL(string: "marten://item")!)
        XCTAssertNil(action)
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
