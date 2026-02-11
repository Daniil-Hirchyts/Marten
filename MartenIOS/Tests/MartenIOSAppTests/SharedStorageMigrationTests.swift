import MartenCore
import XCTest

final class SharedStorageMigrationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MartenSharedStorageTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        super.tearDown()
    }

    func testMigrationMovesLegacyStoreAndAssetsOnce() throws {
        let legacyRoot = temporaryDirectory.appendingPathComponent("legacy", isDirectory: true)
        let sharedRoot = temporaryDirectory.appendingPathComponent("group", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)

        let legacyStore = legacyRoot.appendingPathComponent("MartenCore.sqlite")
        try Data("sqlite".utf8).write(to: legacyStore)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: "\(legacyStore.path)-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: "\(legacyStore.path)-shm"))

        let legacyAssets = legacyRoot.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyAssets, withIntermediateDirectories: true)
        try Data("asset".utf8).write(to: legacyAssets.appendingPathComponent("a.txt"))

        let storage = MartenSharedStorage(
            appGroupIdentifier: "group.com.hirchyts.marten",
            explicitContainerURL: sharedRoot
        )

        let first = try storage.migrateLegacyDataIfNeeded(
            legacyStoreURL: legacyStore,
            legacyAssetsURL: legacyAssets
        )
        XCTAssertTrue(first.movedStoreFiles)
        XCTAssertTrue(first.movedAssets)

        let sharedStore = try storage.sharedStoreURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedStore.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(sharedStore.path)-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(sharedStore.path)-shm"))

        let sharedAssets = try storage.sharedAssetsDirectoryURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedAssets.appendingPathComponent("a.txt").path))

        let second = try storage.migrateLegacyDataIfNeeded(
            legacyStoreURL: legacyStore,
            legacyAssetsURL: legacyAssets
        )
        XCTAssertFalse(second.movedStoreFiles)
        XCTAssertFalse(second.movedAssets)
    }
}
