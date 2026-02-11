import CloudKit
import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class MartenIOSAppContainerSharingTests: XCTestCase {
    private let suiteName = "MartenIOSAppContainerSharingTests"
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

    func testLeaveSharedPinboardDelegatesToRepositoryAndClearsSelection() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let repository = MockPinboardSharingRepository()
        let pinboard = try makeSharedPinboard(in: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider(),
            sharingRepository: repository
        )
        container.setSelectedPinboardID(pinboard.id)

        await container.leaveSharedPinboard(objectID: pinboard.objectID)

        XCTAssertEqual(repository.leaveShareCalls, 1)
        XCTAssertNil(container.selectedPinboardID)
    }

    func testHandleDeepLinkSelectsPinboard() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let pinboard = try makeSharedPinboard(in: persistence)

        let container = MartenIOSAppContainer(
            persistenceController: persistence,
            clipItemStore: store,
            userDefaults: userDefaults,
            syncConfigurationProvider: AlwaysDisabledSyncConfigurationProvider()
        )

        container.handleDeepLink(URL(string: "marten://pinboard/\(pinboard.id.uuidString)")!)
        XCTAssertEqual(container.selectedPinboardID, pinboard.id)
    }

    private func makeSharedPinboard(in persistence: PersistenceController) throws -> Pinboard {
        let context = persistence.viewContext
        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard",
            into: context
        ) as? Pinboard else {
            throw NSError(domain: "test", code: 1)
        }
        pinboard.id = UUID()
        pinboard.name = "Shared"
        pinboard.colorHex = "#AA44EE"
        pinboard.sortOrder = 1
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()

        guard let metadata = NSEntityDescription.insertNewObject(
            forEntityName: "ShareMetadata",
            into: context
        ) as? ShareMetadata else {
            throw NSError(domain: "test", code: 2)
        }
        metadata.id = UUID()
        metadata.shareRecordName = "share-\(UUID().uuidString)"
        metadata.rootRecordName = "root-\(UUID().uuidString)"
        metadata.zoneName = "SharedPinboard-\(UUID().uuidString)"
        metadata.zoneOwnerName = CKCurrentUserDefaultName
        metadata.isOwner = false
        metadata.accessControl = .onlyInvited
        metadata.defaultPermission = .canMakeChanges
        metadata.pinboard = pinboard

        try context.save()
        return pinboard
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

private final class MockPinboardSharingRepository: PinboardSharingRepositoryProtocol, @unchecked Sendable {
    var leaveShareCalls = 0

    func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL {
        URL(string: "https://example.com/share")!
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {}

    func fetchShareDetails(pinboardID: NSManagedObjectID) async throws -> ShareDetails {
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    }

    func updateShareSettings(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> ShareDetails {
        try await fetchShareDetails(pinboardID: pinboardID)
    }

    func inviteParticipant(
        pinboardID: NSManagedObjectID,
        email: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        try await fetchShareDetails(pinboardID: pinboardID)
    }

    func updateParticipantPermission(
        pinboardID: NSManagedObjectID,
        participantID: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        try await fetchShareDetails(pinboardID: pinboardID)
    }

    func removeParticipant(
        pinboardID: NSManagedObjectID,
        participantID: String
    ) async throws -> ShareDetails {
        try await fetchShareDetails(pinboardID: pinboardID)
    }

    func stopSharing(pinboardID: NSManagedObjectID) async throws {}

    func leaveShare(pinboardID: NSManagedObjectID) async throws {
        leaveShareCalls += 1
    }

    func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws {}
}
