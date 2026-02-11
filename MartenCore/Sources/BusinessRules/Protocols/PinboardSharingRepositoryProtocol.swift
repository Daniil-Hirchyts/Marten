import CloudKit
import CoreData
import Foundation

/// Contract for pinboard sharing operations.
public protocol PinboardSharingRepositoryProtocol: Sendable {
    func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL

    func acceptShare(metadata: CKShare.Metadata) async throws
    func fetchShareDetails(pinboardID: NSManagedObjectID) async throws -> ShareDetails
    func updateShareSettings(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> ShareDetails
    func inviteParticipant(
        pinboardID: NSManagedObjectID,
        email: String,
        permission: SharePermission
    ) async throws -> ShareDetails
    func updateParticipantPermission(
        pinboardID: NSManagedObjectID,
        participantID: String,
        permission: SharePermission
    ) async throws -> ShareDetails
    func removeParticipant(
        pinboardID: NSManagedObjectID,
        participantID: String
    ) async throws -> ShareDetails
    func stopSharing(pinboardID: NSManagedObjectID) async throws
    func leaveShare(pinboardID: NSManagedObjectID) async throws
    func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws
}
