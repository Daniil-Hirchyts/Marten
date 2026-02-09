import XCTest
@testable import MartenCore

final class IgnoredAppsManagerTests: XCTestCase {
    private func makeCleanDefaults(suiteName: String = "test-ignored-apps") -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultAppsPopulatedOnFirstLaunch() {
        let defaults = makeCleanDefaults()
        let manager = IgnoredAppsManager(userDefaults: defaults)

        let expectedBundleIdentifiers = Set(IgnoredAppsManager.defaultIgnoredApps.map { $0.bundleIdentifier })
        let actualBundleIdentifiers = Set(manager.ignoredApps.map { $0.bundleIdentifier })

        XCTAssertEqual(actualBundleIdentifiers, expectedBundleIdentifiers)
    }

    func testAddApp() {
        let defaults = makeCleanDefaults()
        let manager = IgnoredAppsManager(userDefaults: defaults)
        let originalCount = manager.ignoredApps.count

        let app = IgnoredApp(bundleIdentifier: "com.example.app", name: "Example", addedAt: Date())
        manager.add(app)

        XCTAssertTrue(manager.contains(bundleIdentifier: "com.example.app"))
        XCTAssertEqual(manager.ignoredApps.count, originalCount + 1)
    }

    func testRemoveApp() {
        let defaults = makeCleanDefaults()
        let manager = IgnoredAppsManager(userDefaults: defaults)

        let app = IgnoredApp(bundleIdentifier: "com.example.remove", name: "Remove Me", addedAt: Date())
        manager.add(app)
        XCTAssertTrue(manager.contains(bundleIdentifier: "com.example.remove"))

        manager.remove(bundleIdentifier: "com.example.remove")
        XCTAssertFalse(manager.contains(bundleIdentifier: "com.example.remove"))
    }

    func testIsIgnored() {
        let defaults = makeCleanDefaults()
        let manager = IgnoredAppsManager(userDefaults: defaults)

        for app in IgnoredAppsManager.defaultIgnoredApps {
            XCTAssertTrue(manager.isIgnored(bundleIdentifier: app.bundleIdentifier))
        }
        XCTAssertFalse(manager.isIgnored(bundleIdentifier: "com.example.unknown"))
    }

    func testPersistence() {
        let suiteName = "test-ignored-apps"
        let defaults = makeCleanDefaults(suiteName: suiteName)

        do {
            let manager = IgnoredAppsManager(userDefaults: defaults)
            let app = IgnoredApp(bundleIdentifier: "com.example.persist", name: "Persist", addedAt: Date())
            manager.add(app)
            XCTAssertTrue(manager.contains(bundleIdentifier: "com.example.persist"))
        }

        let defaultsAgain = UserDefaults(suiteName: suiteName)!
        let managerAgain = IgnoredAppsManager(userDefaults: defaultsAgain)
        XCTAssertTrue(managerAgain.contains(bundleIdentifier: "com.example.persist"))
    }

    func testDoesNotDuplicateOnReinitialization() {
        let suiteName = "test-ignored-apps"
        let defaults = makeCleanDefaults(suiteName: suiteName)

        let manager = IgnoredAppsManager(userDefaults: defaults)
        let managerAgain = IgnoredAppsManager(userDefaults: UserDefaults(suiteName: suiteName)!)

        let expectedCount = IgnoredAppsManager.defaultIgnoredApps.count
        XCTAssertEqual(manager.ignoredApps.count, expectedCount)
        XCTAssertEqual(managerAgain.ignoredApps.count, expectedCount)

        let uniqueIDs = Set(managerAgain.ignoredApps.map { $0.bundleIdentifier })
        XCTAssertEqual(uniqueIDs.count, expectedCount)
    }
}
