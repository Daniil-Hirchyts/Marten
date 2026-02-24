import CloudKit
import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

final class DashboardRefactorTests: XCTestCase {
    func testCopyTextBuilderBestEffortPrefersPlainTextThenPrimaryTextAndTrims() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let first = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("  Alpha  ")],
                primaryText: "  Alpha  ",
                itemType: .text
            ),
            isUserCreated: true
        )
        let second = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("  Beta  ")],
                primaryText: "  Beta  ",
                itemType: .text
            ),
            isUserCreated: true
        )

        let builder = DashboardCopyTextBuilder()
        let text = builder.buildText(for: [first, second], mode: .bestEffort)

        XCTAssertEqual(text, "Alpha\nBeta")
    }

    func testCopyTextBuilderPlainTextTrims() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("  Primary  ")],
                primaryText: "  Primary  ",
                itemType: .text
            ),
            isUserCreated: true
        )

        let builder = DashboardCopyTextBuilder()
        let text = builder.buildText(for: [item], mode: .plainText)

        XCTAssertEqual(text, "Primary")
    }

    func testSharePayloadBuilderBuildsURLsAndImagePayloads() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let existingFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("marten-test-file.txt")
        try "hello".data(using: .utf8)?.write(to: URL(fileURLWithPath: existingFilePath))
        defer { try? FileManager.default.removeItem(atPath: existingFilePath) }

        let fileItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText(existingFilePath)],
                primaryText: existingFilePath,
                itemType: .file
            ),
            isUserCreated: true
        )

        let urlItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("example.com")],
                primaryText: "example.com",
                itemType: .url
            ),
            isUserCreated: true
        )

        let imageItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Caption")],
                primaryText: "Caption",
                itemType: .image
            ),
            isUserCreated: true
        )
        imageItem.thumbnailPath = existingFilePath
        try persistence.viewContext.save()

        struct StubFileManager: DashboardFileManaging {
            let handler: (String) -> Bool
            func fileExists(atPath path: String) -> Bool { handler(path) }
        }
        struct StubImageLoader: DashboardImageLoading {
            let handler: (String) -> Any?
            func loadImage(atPath path: String) -> Any? { handler(path) }
        }

        let sentinel = NSObject()
        let builder = DashboardSharePayloadBuilder(
            fileManager: StubFileManager { path in
                FileManager.default.fileExists(atPath: path)
            },
            imageLoader: StubImageLoader { _ in sentinel }
        )

        let payloads = builder.payloads(for: [fileItem, urlItem, imageItem])

        XCTAssertTrue(payloads.contains(where: { ($0 as? URL)?.path == existingFilePath }))
        XCTAssertTrue(payloads.contains(where: { ($0 as? URL)?.absoluteString == "https://example.com" }))
        XCTAssertTrue(payloads.contains(where: { ($0 as? NSObject) === sentinel }))
        XCTAssertTrue(payloads.contains(where: { ($0 as? String) == "Caption" }))
    }

    @MainActor
    func testItemActionServiceCopyWritesToClipboard() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let commandService = ClipItemCommandService(store: store)
        let resolver = CoreDataDashboardClipItemResolver(viewContext: persistence.viewContext)

        let first = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("First")],
                primaryText: "First",
                itemType: .text
            ),
            isUserCreated: true
        )
        let second = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Second Plain")],
                primaryText: "Second Plain",
                itemType: .text
            ),
            isUserCreated: true
        )

        final class SpyClipboardWriter: DashboardClipboardWriting {
            private(set) var written: [String] = []
            func setString(_ string: String) { written.append(string) }
        }

        let clipboard = SpyClipboardWriter()
        let dependencies = DashboardDependencies(
            clipboardWriter: clipboard,
            fileManager: SystemDashboardFileManager(),
            imageLoader: SystemDashboardImageLoader()
        )
        let service = DashboardItemActionService(dependencies: dependencies)

        let copied = await service.copyItems(
            objectIDs: [first.objectID, second.objectID],
            resolver: resolver,
            commandService: commandService,
            mode: .bestEffort
        )

        XCTAssertEqual(copied, "First\nSecond Plain")
        XCTAssertEqual(clipboard.written.last, "First\nSecond Plain")
    }

    @MainActor
    func testViewModelIsItemVisibleHidesItemsAssignedToLockedPinboardsInAll() throws {
        final class StubLockStateStore: PinboardLockStateProviding {
            var isAuthenticating: Bool = false
            var locked: Set<UUID> = []
            var accessible: Set<UUID> = []

            func isLocked(_ pinboardID: UUID) -> Bool { locked.contains(pinboardID) }
            func canAccess(_ pinboardID: UUID) -> Bool { accessible.contains(pinboardID) }
            func setLock(_ enabled: Bool, for pinboardID: UUID) { }
            func lockNow(pinboardID: UUID) { }
            func unlock(pinboardID: UUID, pinboardName: String) async -> Bool { true }
            func reconcile(validPinboardIDs: Set<UUID>) { }
        }

        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try store.createPinboard(name: "Secret", colorHex: "#111111")
        let item = try store.createTextItem(text: "Hidden")
        try store.addItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        let lockState = StubLockStateStore()
        lockState.locked = [pinboard.id]
        lockState.accessible = []

        let model = DashboardViewModel(dependencies: .live)
        let isVisible = model.isItemVisible(item, selectedPinboardID: nil, lockStateStore: lockState)

        XCTAssertFalse(isVisible)
    }

    @MainActor
    func testReconcilePinboardStateClearsLocksForSharedPinboards() throws {
        let suiteName = "DashboardRefactorTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test user defaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let privatePinboard = try store.createPinboard(name: "Private", colorHex: "#111111")
        let sharedPinboard = try store.createPinboard(name: "Shared", colorHex: "#222222")

        let context = persistence.viewContext
        try context.performAndWaitThrowing {
            guard let shared = try context.existingObject(with: sharedPinboard.objectID) as? Pinboard else {
                XCTFail("Missing shared pinboard object")
                return
            }
            guard let metadata = NSEntityDescription.insertNewObject(
                forEntityName: "ShareMetadata",
                into: context
            ) as? ShareMetadata else {
                XCTFail("Failed to insert ShareMetadata")
                return
            }
            metadata.id = UUID()
            metadata.shareRecordName = "share-\(UUID().uuidString)"
            metadata.rootRecordName = "root-\(UUID().uuidString)"
            metadata.zoneName = "SharedPinboard-\(UUID().uuidString)"
            metadata.zoneOwnerName = CKCurrentUserDefaultName
            metadata.isOwner = true
            metadata.accessControl = .onlyInvited
            metadata.defaultPermission = .canMakeChanges
            metadata.pinboard = shared
            try context.save()
        }

        let sharedInContext = try context.performAndWaitThrowing {
            guard let shared = try context.existingObject(with: sharedPinboard.objectID) as? Pinboard else {
                throw NSError(domain: "DashboardRefactorTests", code: 1)
            }
            return shared
        }

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: DashboardAlwaysDisabledSyncConfigurationProvider()
        )
        container.lockStateStore.setLock(true, for: privatePinboard.id)
        container.lockStateStore.setLock(true, for: sharedInContext.id)

        let viewModel = DashboardViewModel(dependencies: .live)
        viewModel.reconcilePinboardState(
            container: container,
            customPinboards: [privatePinboard, sharedInContext]
        )

        XCTAssertTrue(container.lockStateStore.isLocked(privatePinboard.id))
        XCTAssertFalse(container.lockStateStore.isLocked(sharedInContext.id))
    }
}

private struct DashboardAlwaysDisabledSyncConfigurationProvider: MartenIOSSyncConfigurationProviding {
    func canUseCloudKit(containerIdentifier: String) -> Bool {
        false
    }

    func isSyncEnabled(_ userDefaults: UserDefaults) -> Bool {
        false
    }
}
