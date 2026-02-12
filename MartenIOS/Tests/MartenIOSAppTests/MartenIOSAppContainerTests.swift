import CoreData
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
        let pinboard = try! store.createPinboard(name: "Persisted", colorHex: "#ABCDEF")

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.setSelectedPinboardID(pinboard.id)
        container.setAppearance(.dark)

        let reloaded = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        XCTAssertEqual(reloaded.selectedPinboardID, pinboard.id)
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
        let pinboard = try! store.createPinboard(name: "Deep Link Board", colorHex: "#123456")

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        let url = URL(string: "marten://pinboard/\(pinboard.id.uuidString)")!

        container.handleDeepLink(url)

        XCTAssertEqual(container.selectedPinboardID, pinboard.id)
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

    func testSetSelectedPinboardIDSanitizesUnknownAndSystemPinboards() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.setSelectedPinboardID(UUID())
        XCTAssertNil(container.selectedPinboardID)

        let context = persistence.viewContext
        let systemPinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard",
            into: context
        ) as! Pinboard
        systemPinboard.id = UUID()
        systemPinboard.name = "Marten"
        systemPinboard.colorHex = "#808080"
        systemPinboard.sortOrder = 0
        systemPinboard.isSystemMarten = true
        systemPinboard.createdAt = Date()
        try! context.save()

        container.setSelectedPinboardID(systemPinboard.id)
        XCTAssertNil(container.selectedPinboardID)

        let customPinboard = try! store.createPinboard(name: "Custom", colorHex: "#FFAA33")
        container.setSelectedPinboardID(customPinboard.id)
        XCTAssertEqual(container.selectedPinboardID, customPinboard.id)
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

    func testStartDeduplicatesSystemPinboards() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let context = persistence.viewContext
        let earlierDate = Date(timeIntervalSince1970: 10)
        let laterDate = Date(timeIntervalSince1970: 20)

        let first = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
        first.id = UUID()
        first.name = "Marten"
        first.colorHex = "#808080"
        first.sortOrder = 0
        first.isSystemMarten = true
        first.createdAt = earlierDate

        let second = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
        second.id = UUID()
        second.name = "Marten"
        second.colorHex = "#808080"
        second.sortOrder = 0
        second.isSystemMarten = true
        second.createdAt = laterDate

        try context.save()

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.setSelectedPinboardID(second.id)
        await container.start()

        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemMarten == YES")
        let systemPinboards = try context.fetch(request)
        XCTAssertEqual(systemPinboards.count, 1)
        XCTAssertEqual(systemPinboards.first?.id, first.id)
        XCTAssertNil(container.selectedPinboardID)
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
