import CloudKit
import CoreData
import Foundation

/// Domain-level wrapper around ShareCoordinator that enforces feature flags,
/// lock state, and permission checks before delegating to the share coordinator.
public final class PinboardSharingRepository: PinboardSharingRepositoryProtocol, @unchecked Sendable {
    private let shareCoordinator: ShareCoordinator
    private let persistenceController: PersistenceController
    private let isPinboardLocked: (@MainActor @Sendable (UUID) -> Bool)?

    public init(
        shareCoordinator: ShareCoordinator,
        persistenceController: PersistenceController,
        isPinboardLocked: (@MainActor @Sendable (UUID) -> Bool)? = nil
    ) {
        self.shareCoordinator = shareCoordinator
        self.persistenceController = persistenceController
        self.isPinboardLocked = isPinboardLocked
    }

    public func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        if localState.isSystemMarten {
            throw PinboardSharingError.insufficientPermission
        }
        if let isPinboardLocked {
            let locked = await MainActor.run {
                isPinboardLocked(localState.id)
            }
            if locked {
                throw PinboardSharingError.cannotShareLockedPinboard
            }
        }

        return try await shareCoordinator.createShare(
            pinboardID: pinboardID,
            accessControl: accessControl,
            defaultPermission: defaultPermission
        )
    }

    public func acceptShare(metadata: CKShare.Metadata) async throws {
        try ensureFeatureEnabled()
        try await shareCoordinator.acceptShare(metadata: metadata)
    }

    public func fetchShareDetails(pinboardID: NSManagedObjectID) async throws -> ShareDetails {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }
        return try await shareCoordinator.fetchShareDetails(pinboardID: pinboardID)
    }

    public func updateShareSettings(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> ShareDetails {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }
        guard localState.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        return try await shareCoordinator.updateShareSettings(
            pinboardID: pinboardID,
            accessControl: accessControl,
            defaultPermission: defaultPermission
        )
    }

    public func inviteParticipant(
        pinboardID: NSManagedObjectID,
        email: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }
        guard localState.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        return try await shareCoordinator.inviteParticipant(
            pinboardID: pinboardID,
            email: email,
            permission: permission
        )
    }

    public func updateParticipantPermission(
        pinboardID: NSManagedObjectID,
        participantID: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }
        guard localState.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        return try await shareCoordinator.updateParticipantPermission(
            pinboardID: pinboardID,
            participantID: participantID,
            permission: permission
        )
    }

    public func removeParticipant(
        pinboardID: NSManagedObjectID,
        participantID: String
    ) async throws -> ShareDetails {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }
        guard localState.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        return try await shareCoordinator.removeParticipant(
            pinboardID: pinboardID,
            participantID: participantID
        )
    }

    public func stopSharing(pinboardID: NSManagedObjectID) async throws {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        try await shareCoordinator.stopSharing(pinboardID: pinboardID)
    }

    public func leaveShare(pinboardID: NSManagedObjectID) async throws {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }

        try await shareCoordinator.leaveShare(pinboardID: pinboardID)
    }

    public func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws {
        try ensureFeatureEnabled()
        let localState = try loadLocalState(pinboardID: pinboardID)
        guard localState.isShared else {
            throw PinboardSharingError.shareNotFound
        }

        try await shareCoordinator.refreshShareParticipants(pinboardID: pinboardID)
    }

    private func ensureFeatureEnabled() throws {
        guard SharedPinboardsFeatureFlag.isEnabled else {
            throw PinboardSharingError.featureDisabled
        }
    }

    private func loadLocalState(pinboardID: NSManagedObjectID) throws -> LocalShareState {
        let context = persistenceController.newBackgroundContext()
        return try context.performAndWait {
            guard let pinboard = try context.existingObject(with: pinboardID) as? Pinboard else {
                throw PinboardSharingError.shareNotFound
            }
            return LocalShareState(
                id: pinboard.id,
                isSystemMarten: pinboard.isSystemMarten,
                isShared: pinboard.shareMetadata != nil,
                isOwner: pinboard.shareMetadata?.isOwner == true
            )
        }
    }
}

private struct LocalShareState {
    let id: UUID
    let isSystemMarten: Bool
    let isShared: Bool
    let isOwner: Bool
}
