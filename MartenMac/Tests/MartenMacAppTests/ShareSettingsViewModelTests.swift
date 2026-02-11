import CloudKit
import CoreData
import MartenCore
import XCTest

@testable import MartenMac

@MainActor
final class ShareSettingsViewModelTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testOnAppearLoadsShareDetailsWhenShareExists() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboardID = try makePinboardID(in: persistence)
        let repository = MockPinboardSharingRepository()
        let details = makeDetails(
            accessControl: .anyoneWithLink,
            defaultPermission: .viewOnly,
            participants: [
                ShareParticipantInfo(
                    id: "record:owner",
                    displayName: "Owner",
                    email: "owner@example.com",
                    permission: .owner,
                    acceptanceStatus: .accepted,
                    isOwner: true,
                    isCurrentUser: true
                )
            ]
        )
        repository.fetchShareDetailsResult = .success(details)

        let viewModel = ShareSettingsViewModel(
            pinboardID: pinboardID,
            sharingRepository: repository,
            initialAccessControl: .onlyInvited,
            initialDefaultPermission: .canMakeChanges,
            initialShareURL: URL(string: "https://example.com/seed")
        )

        await viewModel.onAppear()

        XCTAssertEqual(repository.fetchShareDetailsCalls, 1)
        XCTAssertEqual(viewModel.accessControl, .anyoneWithLink)
        XCTAssertEqual(viewModel.defaultPermission, .viewOnly)
        XCTAssertEqual(viewModel.participants.count, 1)
    }

    func testInviteParticipantRejectsInvalidEmail() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboardID = try makePinboardID(in: persistence)
        let repository = MockPinboardSharingRepository()

        let viewModel = ShareSettingsViewModel(
            pinboardID: pinboardID,
            sharingRepository: repository,
            initialShareURL: URL(string: "https://example.com/share")
        )
        viewModel.inviteEmail = "invalid-email"

        _ = await viewModel.inviteParticipant()

        XCTAssertEqual(repository.inviteParticipantCalls, 0)
        XCTAssertEqual(viewModel.inviteValidationMessage, "Enter a valid email address.")
    }

    func testUpdateShareSettingsIfNeededAppliesUpdatedDetails() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboardID = try makePinboardID(in: persistence)
        let repository = MockPinboardSharingRepository()
        repository.updateShareSettingsResult = .success(
            makeDetails(
                accessControl: .anyoneWithLink,
                defaultPermission: .viewOnly
            )
        )

        let viewModel = ShareSettingsViewModel(
            pinboardID: pinboardID,
            sharingRepository: repository,
            initialAccessControl: .onlyInvited,
            initialDefaultPermission: .canMakeChanges,
            initialShareURL: URL(string: "https://example.com/share")
        )
        viewModel.accessControl = .anyoneWithLink
        viewModel.defaultPermission = .viewOnly

        await viewModel.updateShareSettingsIfNeeded()

        XCTAssertEqual(repository.updateShareSettingsCalls, 1)
        XCTAssertEqual(viewModel.accessControl, .anyoneWithLink)
        XCTAssertEqual(viewModel.defaultPermission, .viewOnly)
        XCTAssertFalse(viewModel.hasPendingSettingsChanges)
    }

    func testRemovePendingParticipantCallsRepository() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pinboardID = try makePinboardID(in: persistence)
        let repository = MockPinboardSharingRepository()
        let participant = ShareParticipantInfo(
            id: "record:abc",
            displayName: "Alex",
            email: "alex@example.com",
            permission: .canMakeChanges,
            acceptanceStatus: .accepted,
            isOwner: false,
            isCurrentUser: false
        )
        repository.removeParticipantResult = .success(
            makeDetails(
                accessControl: .onlyInvited,
                defaultPermission: .canMakeChanges,
                participants: []
            )
        )

        let viewModel = ShareSettingsViewModel(
            pinboardID: pinboardID,
            sharingRepository: repository,
            initialShareURL: URL(string: "https://example.com/share")
        )
        viewModel.requestRemoveParticipant(participant)

        await viewModel.removePendingParticipant()

        XCTAssertEqual(repository.removeParticipantCalls, 1)
        XCTAssertNil(viewModel.pendingParticipantRemoval)
        XCTAssertTrue(viewModel.participants.isEmpty)
    }

    private func makePinboardID(in persistence: PersistenceController) throws -> NSManagedObjectID {
        let context = persistence.viewContext
        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard",
            into: context
        ) as? Pinboard else {
            throw TestError.failed
        }
        pinboard.id = UUID()
        pinboard.name = "Test"
        pinboard.colorHex = "#00AAFF"
        pinboard.sortOrder = 0
        pinboard.isSystemMarten = false
        pinboard.createdAt = Date()
        try context.save()
        return pinboard.objectID
    }

    private func makeDetails(
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission,
        participants: [ShareParticipantInfo] = []
    ) -> ShareDetails {
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: accessControl,
            defaultPermission: defaultPermission,
            isOwner: true,
            participants: participants
        )
    }
}

private final class MockPinboardSharingRepository: PinboardSharingRepositoryProtocol, @unchecked Sendable {
    var createShareCalls = 0
    var fetchShareDetailsCalls = 0
    var updateShareSettingsCalls = 0
    var inviteParticipantCalls = 0
    var updateParticipantPermissionCalls = 0
    var removeParticipantCalls = 0
    var stopSharingCalls = 0

    var createShareResult: Result<URL, Error> = .success(URL(string: "https://example.com/share")!)
    var fetchShareDetailsResult: Result<ShareDetails, Error> = .success(
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    )
    var updateShareSettingsResult: Result<ShareDetails, Error> = .success(
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    )
    var inviteParticipantResult: Result<ShareDetails, Error> = .success(
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    )
    var updateParticipantPermissionResult: Result<ShareDetails, Error> = .success(
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    )
    var removeParticipantResult: Result<ShareDetails, Error> = .success(
        ShareDetails(
            shareURL: URL(string: "https://example.com/share"),
            accessControl: .onlyInvited,
            defaultPermission: .canMakeChanges,
            isOwner: true,
            participants: []
        )
    )

    func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL {
        createShareCalls += 1
        return try createShareResult.get()
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {}

    func fetchShareDetails(pinboardID: NSManagedObjectID) async throws -> ShareDetails {
        fetchShareDetailsCalls += 1
        return try fetchShareDetailsResult.get()
    }

    func updateShareSettings(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> ShareDetails {
        updateShareSettingsCalls += 1
        return try updateShareSettingsResult.get()
    }

    func inviteParticipant(
        pinboardID: NSManagedObjectID,
        email: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        inviteParticipantCalls += 1
        return try inviteParticipantResult.get()
    }

    func updateParticipantPermission(
        pinboardID: NSManagedObjectID,
        participantID: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        updateParticipantPermissionCalls += 1
        return try updateParticipantPermissionResult.get()
    }

    func removeParticipant(
        pinboardID: NSManagedObjectID,
        participantID: String
    ) async throws -> ShareDetails {
        removeParticipantCalls += 1
        return try removeParticipantResult.get()
    }

    func stopSharing(pinboardID: NSManagedObjectID) async throws {
        stopSharingCalls += 1
    }

    func leaveShare(pinboardID: NSManagedObjectID) async throws {}
    func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws {}
}
