import MartenCore
import Foundation
import XCTest

@testable import MartenMac

@MainActor
final class FirstLaunchContentSeederTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "FirstLaunchContentSeederTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testSeedIfNeededCreatesStarterPinboardsAndCards() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let seeder = FirstLaunchContentSeeder(clipItemStore: store, userDefaults: defaults)

        seeder.seedIfNeeded()

        let pinboards = try store.fetchPinboards().filter { !$0.isSystemMarten }
        let pinboardNames = Set(pinboards.map(\.name))
        let items = try store.fetchRecentItems(limit: 20)
        let itemTypes = Set(items.map(\.itemTypeValue))

        XCTAssertEqual(pinboards.count, 3)
        XCTAssertEqual(pinboardNames, Set(["Work", "Learning", "Personal"]))
        XCTAssertEqual(items.count, 6)
        XCTAssertTrue(itemTypes.contains(.code))
        XCTAssertTrue(itemTypes.contains(.url))
        XCTAssertTrue(
            items.allSatisfy { item in
                item.pinboards?.contains(where: { !$0.isSystemMarten }) == true
            }
        )
        XCTAssertTrue(defaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent))
    }

    func testSeedIfNeededDoesNotDuplicateContent() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let seeder = FirstLaunchContentSeeder(clipItemStore: store, userDefaults: defaults)

        seeder.seedIfNeeded()
        let firstItemCount = try store.fetchRecentItems(limit: 20).count
        let firstPinboardCount = try store.fetchPinboards().filter { !$0.isSystemMarten }.count

        seeder.seedIfNeeded()

        let secondItemCount = try store.fetchRecentItems(limit: 20).count
        let secondPinboardCount = try store.fetchPinboards().filter { !$0.isSystemMarten }.count

        XCTAssertEqual(firstItemCount, secondItemCount)
        XCTAssertEqual(firstPinboardCount, secondPinboardCount)
    }

    func testSeedIfNeededSkipsWhenStoreAlreadyHasItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(text: "Existing item")
        let seeder = FirstLaunchContentSeeder(clipItemStore: store, userDefaults: defaults)

        seeder.seedIfNeeded()

        let items = try store.fetchRecentItems(limit: 20)
        let customPinboards = try store.fetchPinboards().filter { !$0.isSystemMarten }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(customPinboards.count, 0)
        XCTAssertTrue(defaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent))
    }

    func testSeedIfNeededSkipsForAlreadyOnboardedInstall() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let seeder = FirstLaunchContentSeeder(clipItemStore: store, userDefaults: defaults)

        seeder.seedIfNeeded()

        let items = try store.fetchRecentItems(limit: 20)
        let customPinboards = try store.fetchPinboards().filter { !$0.isSystemMarten }

        XCTAssertEqual(items.count, 0)
        XCTAssertEqual(customPinboards.count, 0)
        XCTAssertTrue(defaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent))
    }

    func testSeedIfNeededRecoversFromInterruptedSeedingWithoutDuplicates() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(
            text: """
                Sprint checklist:
                - Review pull requests
                - Publish release notes
                - Send status update
                """
        )
        defaults.set(true, forKey: AppSettingsKeys.starterContentSeedInProgress)

        let seeder = FirstLaunchContentSeeder(clipItemStore: store, userDefaults: defaults)
        seeder.seedIfNeeded()

        let items = try store.fetchRecentItems(limit: 20)
        let customPinboards = try store.fetchPinboards().filter { !$0.isSystemMarten }

        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(customPinboards.count, 3)
        XCTAssertTrue(
            items.contains(where: {
                $0.itemTypeValue == .text
                    && $0.primaryText?.contains("Sprint checklist:") == true
            })
        )
        XCTAssertTrue(defaults.bool(forKey: AppSettingsKeys.hasSeededStarterContent))
        XCTAssertFalse(defaults.bool(forKey: AppSettingsKeys.starterContentSeedInProgress))
    }
}
