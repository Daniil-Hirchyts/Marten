import CloudKit
import CoreData
import Foundation

/// Implements the PinboardSharingRepositoryProtocol using CloudKit native sharing (CKShare).
///
/// Manages the full share lifecycle: create, accept, stop, leave, participant refresh, and owner management.
public final class ShareCoordinator: @unchecked Sendable {
    private let cloudKitManager: CloudKitManager
    private let persistenceController: PersistenceController
    private let recordMapper: CloudRecordMapper

    public init(
        cloudKitManager: CloudKitManager,
        persistenceController: PersistenceController,
        recordMapper: CloudRecordMapper
    ) {
        self.cloudKitManager = cloudKitManager
        self.persistenceController = persistenceController
        self.recordMapper = recordMapper
    }

    // MARK: - Create Share

    /// Creates a CKShare for the specified pinboard.
    ///
    /// Flow: validate → create zone → upsert root CKPinboard → create CKShare → configure → save → persist ShareMetadata → return URL
    public func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL {
        let data = try loadPinboardData(pinboardID: pinboardID)

        // Create dedicated shared zone
        let zoneName = "SharedPinboard-\(data.id.uuidString)"
        let zoneID = try await cloudKitManager.setupSharedZone(named: zoneName)

        // Create root CKPinboard record in shared zone
        let rootRecordID = CKRecord.ID.pinboardID(data.id, zoneID: zoneID)
        let rootRecord = CKRecord(recordType: CloudRecordType.pinboard.rawValue, recordID: rootRecordID)
        rootRecord.setUUID(data.id, for: PinboardField.id.rawValue)
        rootRecord.setString(data.name, for: PinboardField.name.rawValue)
        rootRecord.setString(data.colorHex, for: PinboardField.colorHex.rawValue)
        rootRecord.setInt16(data.sortOrder, for: PinboardField.sortOrder.rawValue)
        rootRecord.setBool(data.isSystemMarten, for: PinboardField.isSystemMarten.rawValue)
        rootRecord.setDate(data.createdAt, for: PinboardField.createdAt.rawValue)
        rootRecord.setDate(Date(), for: PinboardField.modifiedAt.rawValue)
        rootRecord.setString(data.iconName, for: PinboardField.iconName.rawValue)

        // Create and configure CKShare
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = data.name
        share.publicPermission = publicPermission(
            accessControl: accessControl,
            defaultPermission: defaultPermission
        )

        // Save root + share to CloudKit
        try await cloudKitManager.privateDatabase.save(records: [rootRecord, share], deleting: [])

        let shareURL: URL
        if let url = share.url {
            shareURL = url
        } else {
            // In some environments, URL population on the local CKShare instance can lag.
            // Re-fetch once to avoid surfacing a false "Invalid share metadata" error.
            let refetched = try await cloudKitManager.privateDatabase.record(for: share.recordID)
            guard let refetchedShare = refetched as? CKShare, let url = refetchedShare.url else {
                throw PinboardSharingError.invalidShareMetadata
            }
            shareURL = url
        }

        // Persist ShareMetadata locally
        try persistMetadataForCreatedShare(
            pinboardID: pinboardID,
            share: share,
            zoneName: zoneName,
            rootRecordName: rootRecord.recordID.recordName,
            accessControl: accessControl,
            defaultPermission: defaultPermission,
            shareURL: shareURL
        )

        return shareURL
    }

    // MARK: - Accept Share

    /// Accepts a share invitation and persists the ShareMetadata locally.
    public func acceptShare(metadata: CKShare.Metadata) async throws {
        do {
            try await cloudKitManager.acceptShare(metadata)
        } catch {
            throw PinboardSharingError.acceptShareFailed
        }

        // The shared data will arrive via SharedInboundSyncEngine.
        // Persist minimal ShareMetadata to track the shared zone.
        let bgContext = persistenceController.newBackgroundContext()
        try bgContext.performAndWait {
            let rootRecordName = metadata.rootRecordID.recordName

            // Check if we already have this share
            let request = ShareMetadata.fetchRequest()
            request.predicate = NSPredicate(format: "rootRecordName == %@", rootRecordName)
            request.fetchLimit = 1
            guard try bgContext.fetch(request).isEmpty else { return }

            // Create a placeholder pinboard until inbound shared sync writes the actual payload.
            guard let pinboard = NSEntityDescription.insertNewObject(
                forEntityName: "Pinboard",
                into: bgContext
            ) as? Pinboard else {
                throw PinboardSharingError.acceptShareFailed
            }

            let pinboardUUID = metadata.rootRecordID.extractUUID() ?? UUID()
            pinboard.id = pinboardUUID
            pinboard.name = "Shared Pinboard"
            pinboard.colorHex = "#808080"
            pinboard.sortOrder = 999
            pinboard.isSystemMarten = false
            pinboard.createdAt = Date()

            guard let shareMetadata = NSEntityDescription.insertNewObject(
                forEntityName: "ShareMetadata",
                into: bgContext
            ) as? ShareMetadata else {
                throw PinboardSharingError.acceptShareFailed
            }

            shareMetadata.id = UUID()
            shareMetadata.shareRecordName = metadata.share.recordID.recordName
            shareMetadata.rootRecordName = rootRecordName
            shareMetadata.zoneName = metadata.rootRecordID.zoneID.zoneName
            shareMetadata.zoneOwnerName = metadata.rootRecordID.zoneID.ownerName
            shareMetadata.isOwner = false
            shareMetadata.accessControl = .onlyInvited
            shareMetadata.defaultPermission = .canMakeChanges
            shareMetadata.shareURL = metadata.share.url?.absoluteString
            shareMetadata.pinboard = pinboard

            try bgContext.save()
        }
    }

    // MARK: - Share Details

    public func fetchShareDetails(pinboardID: NSManagedObjectID) async throws -> ShareDetails {
        do {
            let reference = try loadShareReference(pinboardID: pinboardID)
            let share = try await fetchShareRecord(reference: reference)
            let details = mapShareDetails(share: share, reference: reference)
            try persistShareDetails(pinboardID: pinboardID, details: details)
            return details
        } catch let error as PinboardSharingError {
            throw error
        } catch {
            throw PinboardSharingError.fetchShareDetailsFailed
        }
    }

    public func updateShareSettings(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> ShareDetails {
        do {
            let reference = try loadShareReference(pinboardID: pinboardID)
            guard reference.isOwner else {
                throw PinboardSharingError.ownerOnlyOperation
            }

            let share = try await fetchShareRecord(reference: reference)
            share.publicPermission = publicPermission(
                accessControl: accessControl,
                defaultPermission: defaultPermission
            )

            try await database(for: reference).save(records: [share], deleting: [])

            let details = mapShareDetails(share: share, reference: reference)
            try persistShareDetails(pinboardID: pinboardID, details: details)
            return details
        } catch let error as PinboardSharingError {
            throw error
        } catch {
            throw PinboardSharingError.updateShareSettingsFailed
        }
    }

    public func inviteParticipant(
        pinboardID: NSManagedObjectID,
        email: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        do {
            let reference = try loadShareReference(pinboardID: pinboardID)
            guard reference.isOwner else {
                throw PinboardSharingError.ownerOnlyOperation
            }
            guard permission == .canMakeChanges || permission == .viewOnly else {
                throw PinboardSharingError.insufficientPermission
            }

            let participant: CKShare.Participant
            do {
                participant = try await cloudKitManager.shareParticipant(forEmailAddress: email)
            } catch {
                throw PinboardSharingError.participantLookupFailed
            }

            let share = try await fetchShareRecord(reference: reference)
            let participantID = participantIdentifier(participant)

            if let existing = share.participants.first(where: { participantMatches($0, participantID) }) {
                existing.permission = participantPermission(permission)
            } else {
                participant.permission = participantPermission(permission)
                share.addParticipant(participant)
            }

            try await database(for: reference).save(records: [share], deleting: [])

            let details = mapShareDetails(share: share, reference: reference)
            try persistShareDetails(pinboardID: pinboardID, details: details)
            return details
        } catch let error as PinboardSharingError {
            throw error
        } catch {
            throw PinboardSharingError.inviteParticipantFailed
        }
    }

    public func updateParticipantPermission(
        pinboardID: NSManagedObjectID,
        participantID: String,
        permission: SharePermission
    ) async throws -> ShareDetails {
        do {
            let normalizedID = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else {
                throw PinboardSharingError.invalidParticipantIdentifier
            }
            guard permission == .canMakeChanges || permission == .viewOnly else {
                throw PinboardSharingError.insufficientPermission
            }

            let reference = try loadShareReference(pinboardID: pinboardID)
            guard reference.isOwner else {
                throw PinboardSharingError.ownerOnlyOperation
            }

            let share = try await fetchShareRecord(reference: reference)
            guard let participant = share.participants.first(where: { participantMatches($0, normalizedID) }) else {
                throw PinboardSharingError.invalidParticipantIdentifier
            }

            // Owner participant (including current user owner) cannot be role-edited.
            if participant.role == .owner {
                throw PinboardSharingError.ownerOnlyOperation
            }

            participant.permission = participantPermission(permission)
            try await database(for: reference).save(records: [share], deleting: [])

            let details = mapShareDetails(share: share, reference: reference)
            try persistShareDetails(pinboardID: pinboardID, details: details)
            return details
        } catch let error as PinboardSharingError {
            throw error
        } catch {
            throw PinboardSharingError.updateParticipantPermissionFailed
        }
    }

    public func removeParticipant(
        pinboardID: NSManagedObjectID,
        participantID: String
    ) async throws -> ShareDetails {
        do {
            let normalizedID = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else {
                throw PinboardSharingError.invalidParticipantIdentifier
            }

            let reference = try loadShareReference(pinboardID: pinboardID)
            guard reference.isOwner else {
                throw PinboardSharingError.ownerOnlyOperation
            }

            let share = try await fetchShareRecord(reference: reference)
            guard let participant = share.participants.first(where: { participantMatches($0, normalizedID) }) else {
                throw PinboardSharingError.invalidParticipantIdentifier
            }

            // Never allow removing the owner participant.
            if participant.role == .owner {
                throw PinboardSharingError.ownerOnlyOperation
            }

            share.removeParticipant(participant)
            try await database(for: reference).save(records: [share], deleting: [])

            let details = mapShareDetails(share: share, reference: reference)
            try persistShareDetails(pinboardID: pinboardID, details: details)
            return details
        } catch let error as PinboardSharingError {
            throw error
        } catch {
            throw PinboardSharingError.removeParticipantFailed
        }
    }

    // MARK: - Stop Sharing

    /// Stops sharing a pinboard (owner only). Deletes the CKShare and clears local metadata.
    public func stopSharing(pinboardID: NSManagedObjectID) async throws {
        let reference = try loadShareReference(pinboardID: pinboardID)
        guard reference.isOwner else {
            throw PinboardSharingError.ownerOnlyOperation
        }

        do {
            let shareRecordID = CKRecord.ID(
                recordName: reference.shareRecordName,
                zoneID: CKRecordZone.ID(zoneName: reference.zoneName, ownerName: reference.zoneOwnerName)
            )
            try await cloudKitManager.privateDatabase.save(records: [], deleting: [shareRecordID])
        } catch {
            throw PinboardSharingError.stopSharingFailed
        }

        // Clear local ShareMetadata.
        let bgContext = persistenceController.newBackgroundContext()
        try bgContext.performAndWait {
            guard let pinboard = try bgContext.existingObject(with: pinboardID) as? Pinboard,
                  let meta = pinboard.shareMetadata else { return }
            bgContext.delete(meta)
            try bgContext.save()
        }
    }

    // MARK: - Leave Share

    /// Leaves a shared pinboard (participant). Removes local data and clears zone token.
    public func leaveShare(pinboardID: NSManagedObjectID) async throws {
        let bgContext = persistenceController.newBackgroundContext()

        try bgContext.performAndWait {
            guard let pinboard = try bgContext.existingObject(with: pinboardID) as? Pinboard,
                  let meta = pinboard.shareMetadata else {
                throw PinboardSharingError.shareNotFound
            }

            guard !meta.isOwner else {
                throw PinboardSharingError.ownerOnlyOperation
            }

            // Delete share metadata and the pinboard itself.
            bgContext.delete(meta)
            bgContext.delete(pinboard)
            try bgContext.save()
        }
    }

    // MARK: - Refresh Participants

    /// Fetches latest details and persists refreshed participant/access metadata.
    public func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws {
        _ = try await fetchShareDetails(pinboardID: pinboardID)
    }

    // MARK: - Local Data Loaders

    private func loadPinboardData(pinboardID: NSManagedObjectID) throws -> PinboardData {
        let context = persistenceController.newBackgroundContext()
        return try context.performAndWait {
            guard let pinboard = try context.existingObject(with: pinboardID) as? Pinboard else {
                throw PinboardSharingError.shareNotFound
            }
            return PinboardData(
                id: pinboard.id,
                name: pinboard.name,
                colorHex: pinboard.colorHex,
                sortOrder: pinboard.sortOrder,
                isSystemMarten: pinboard.isSystemMarten,
                createdAt: pinboard.createdAt,
                iconName: pinboard.iconName
            )
        }
    }

    private func loadShareReference(pinboardID: NSManagedObjectID) throws -> ShareReference {
        let context = persistenceController.newBackgroundContext()
        return try context.performAndWait {
            guard let pinboard = try context.existingObject(with: pinboardID) as? Pinboard,
                  let metadata = pinboard.shareMetadata else {
                throw PinboardSharingError.shareNotFound
            }

            return ShareReference(
                pinboardID: pinboardID,
                shareRecordName: metadata.shareRecordName,
                zoneName: metadata.zoneName,
                zoneOwnerName: metadata.zoneOwnerName,
                isOwner: metadata.isOwner,
                accessControlFallback: metadata.accessControl,
                defaultPermissionFallback: metadata.defaultPermission,
                shareURLFallback: metadata.shareURL.flatMap(URL.init(string:))
            )
        }
    }

    // MARK: - Metadata Persistence

    private func persistMetadataForCreatedShare(
        pinboardID: NSManagedObjectID,
        share: CKShare,
        zoneName: String,
        rootRecordName: String,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission,
        shareURL: URL
    ) throws {
        let bgContext = persistenceController.newBackgroundContext()
        try bgContext.performAndWait {
            guard let pinboard = try bgContext.existingObject(with: pinboardID) as? Pinboard else {
                throw PinboardSharingError.shareNotFound
            }

            let metadata: ShareMetadata
            if let existing = pinboard.shareMetadata {
                metadata = existing
            } else {
                guard let inserted = NSEntityDescription.insertNewObject(
                    forEntityName: "ShareMetadata",
                    into: bgContext
                ) as? ShareMetadata else {
                    throw PinboardSharingError.sharedZoneSetupFailed
                }
                inserted.id = UUID()
                inserted.pinboard = pinboard
                metadata = inserted
            }

            metadata.shareRecordName = share.recordID.recordName
            metadata.rootRecordName = rootRecordName
            metadata.zoneName = zoneName
            metadata.zoneOwnerName = CKCurrentUserDefaultName
            metadata.isOwner = true
            metadata.accessControl = accessControl
            metadata.defaultPermission = defaultPermission
            metadata.shareURL = shareURL.absoluteString
            metadata.lastParticipantRefreshAt = Date()

            try bgContext.save()
        }
    }

    private func persistShareDetails(pinboardID: NSManagedObjectID, details: ShareDetails) throws {
        let bgContext = persistenceController.newBackgroundContext()
        try bgContext.performAndWait {
            guard let pinboard = try bgContext.existingObject(with: pinboardID) as? Pinboard,
                  let metadata = pinboard.shareMetadata else {
                throw PinboardSharingError.shareNotFound
            }

            metadata.isOwner = details.isOwner
            metadata.accessControl = details.accessControl
            metadata.defaultPermission = details.defaultPermission
            metadata.shareURL = details.shareURL?.absoluteString
            metadata.lastParticipantRefreshAt = Date()

            try bgContext.save()
        }
    }

    // MARK: - CloudKit Share Fetch/Map

    private func database(for reference: ShareReference) -> CloudKitDatabaseProviding {
        reference.isOwner ? cloudKitManager.privateDatabase : cloudKitManager.sharedDatabase
    }

    private func fetchShareRecord(reference: ShareReference) async throws -> CKShare {
        let zoneID = CKRecordZone.ID(zoneName: reference.zoneName, ownerName: reference.zoneOwnerName)
        let shareRecordID = CKRecord.ID(recordName: reference.shareRecordName, zoneID: zoneID)
        let record = try await database(for: reference).record(for: shareRecordID)
        guard let share = record as? CKShare else {
            throw PinboardSharingError.invalidShareMetadata
        }
        return share
    }

    private func mapShareDetails(share: CKShare, reference: ShareReference) -> ShareDetails {
        let accessAndPermission = mapPublicPermission(
            share.publicPermission,
            fallbackAccess: reference.accessControlFallback,
            fallbackPermission: reference.defaultPermissionFallback
        )
        let participantRows = mapParticipants(share: share)

        let isOwner: Bool = share.currentUserParticipant?.role == .owner || reference.isOwner
        let currentPermission = share.currentUserParticipant.map(sharePermission(from:))

        return ShareDetails(
            shareURL: share.url ?? reference.shareURLFallback,
            accessControl: accessAndPermission.accessControl,
            defaultPermission: isOwner ? accessAndPermission.defaultPermission : (currentPermission ?? reference.defaultPermissionFallback),
            isOwner: isOwner,
            participants: participantRows
        )
    }

    private func mapParticipants(share: CKShare) -> [ShareParticipantInfo] {
        let currentParticipantID = share.currentUserParticipant.map(participantIdentifier)
        let nameFormatter = PersonNameComponentsFormatter()

        let mapped = share.participants.map { participant in
            let id = participantIdentifier(participant)
            let email = Self.normalizedParticipantEmailAddress(
                participant.userIdentity.lookupInfo?.emailAddress
            )

            let formattedName = participant.userIdentity.nameComponents
                .flatMap { nameFormatter.string(from: $0) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayName: String
            if !formattedName.isEmpty {
                displayName = formattedName
            } else if let email, !email.isEmpty {
                displayName = email
            } else if let recordName = participant.userIdentity.userRecordID?.recordName {
                displayName = recordName
            } else {
                displayName = "Unknown participant"
            }

            return ShareParticipantInfo(
                id: id,
                displayName: displayName,
                email: email,
                permission: sharePermission(from: participant),
                acceptanceStatus: acceptanceStatus(from: participant.acceptanceStatus),
                isOwner: participant.role == .owner,
                isCurrentUser: currentParticipantID == id
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.isOwner != rhs.isOwner {
                return lhs.isOwner
            }
            if lhs.isCurrentUser != rhs.isCurrentUser {
                return lhs.isCurrentUser
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func normalizedParticipantEmailAddress(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if value.lowercased().hasPrefix("mailto:") {
            value.removeFirst("mailto:".count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !value.isEmpty else { return nil }

        if let components = URLComponents(string: value), components.scheme != nil {
            return nil
        }

        guard value.contains("@"), !value.hasPrefix("@"), !value.hasSuffix("@") else {
            return nil
        }

        return value
    }

    // MARK: - Permission Mapping

    private func publicPermission(
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) -> CKShare.ParticipantPermission {
        switch accessControl {
        case .onlyInvited:
            return .none
        case .anyoneWithLink:
            switch defaultPermission {
            case .owner, .canMakeChanges:
                return .readWrite
            case .viewOnly:
                return .readOnly
            }
        }
    }

    private func mapPublicPermission(
        _ permission: CKShare.ParticipantPermission,
        fallbackAccess: ShareAccessControl,
        fallbackPermission: SharePermission
    ) -> (accessControl: ShareAccessControl, defaultPermission: SharePermission) {
        switch permission {
        case .none:
            return (.onlyInvited, fallbackPermission)
        case .readOnly:
            return (.anyoneWithLink, .viewOnly)
        case .readWrite:
            return (.anyoneWithLink, .canMakeChanges)
        case .unknown:
            return (fallbackAccess, fallbackPermission)
        @unknown default:
            return (fallbackAccess, fallbackPermission)
        }
    }

    private func participantPermission(_ permission: SharePermission) -> CKShare.ParticipantPermission {
        switch permission {
        case .owner, .canMakeChanges:
            return .readWrite
        case .viewOnly:
            return .readOnly
        }
    }

    private func sharePermission(from participant: CKShare.Participant) -> SharePermission {
        if participant.role == .owner {
            return .owner
        }
        switch participant.permission {
        case .readWrite:
            return .canMakeChanges
        case .readOnly, .none, .unknown:
            return .viewOnly
        @unknown default:
            return .viewOnly
        }
    }

    private func acceptanceStatus(
        from cloudStatus: CKShare.ParticipantAcceptanceStatus
    ) -> ShareParticipantAcceptanceStatus {
        switch cloudStatus {
        case .unknown:
            return .unknown
        case .pending:
            return .pending
        case .accepted:
            return .accepted
        case .removed:
            return .removed
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Participant Identifier Mapping

    private func participantIdentifier(_ participant: CKShare.Participant) -> String {
        if let recordName = participant.userIdentity.userRecordID?.recordName, !recordName.isEmpty {
            return "record:\(recordName)"
        }
        return "participant:\(String(describing: participant.participantID))"
    }

    private func participantMatches(_ participant: CKShare.Participant, _ identifier: String) -> Bool {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if participantIdentifier(participant) == normalized {
            return true
        }

        if let recordName = participant.userIdentity.userRecordID?.recordName {
            if normalized == recordName || normalized == "record:\(recordName)" {
                return true
            }
        }

        let participantIDString = String(describing: participant.participantID)
        return normalized == participantIDString || normalized == "participant:\(participantIDString)"
    }
}

private struct PinboardData {
    let id: UUID
    let name: String
    let colorHex: String
    let sortOrder: Int16
    let isSystemMarten: Bool
    let createdAt: Date
    let iconName: String?
}

private struct ShareReference {
    let pinboardID: NSManagedObjectID
    let shareRecordName: String
    let zoneName: String
    let zoneOwnerName: String
    let isOwner: Bool
    let accessControlFallback: ShareAccessControl
    let defaultPermissionFallback: SharePermission
    let shareURLFallback: URL?
}

extension ShareCoordinator: PinboardSharingRepositoryProtocol {}
