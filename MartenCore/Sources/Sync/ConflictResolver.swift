import CloudKit
import Foundation

public enum ConflictResolution: Equatable, Sendable {
    case keepLocal
    case keepRemote
}

public enum DeletionResolution: Equatable, Sendable {
    case keepRecord
    case deleteRecord
}

public final class ConflictResolver {
    public init() {}

    public func resolveLastWriterWins(local: CKRecord, remote: CKRecord, modifiedAtKey: String) -> ConflictResolution {
        guard let localModified = local.date(for: modifiedAtKey),
              let remoteModified = remote.date(for: modifiedAtKey) else {
            return .keepRemote
        }

        if localModified > remoteModified {
            return .keepLocal
        }
        if remoteModified > localModified {
            return .keepRemote
        }

        return local.recordID.recordName >= remote.recordID.recordName ? .keepLocal : .keepRemote
    }

    public func resolveClipItemAppendOnly(local: CKRecord, remote: CKRecord) -> ConflictResolution {
        let createdKey = ClipItemField.createdAt.rawValue
        guard let localCreated = local.date(for: createdKey),
              let remoteCreated = remote.date(for: createdKey) else {
            return .keepRemote
        }

        if localCreated < remoteCreated {
            return .keepLocal
        }
        if remoteCreated < localCreated {
            return .keepRemote
        }

        return local.recordID.recordName >= remote.recordID.recordName ? .keepLocal : .keepRemote
    }

    public func resolveDeletedWins(localIsDeleted: Bool, remoteIsDeleted: Bool) -> DeletionResolution {
        if localIsDeleted || remoteIsDeleted {
            return .deleteRecord
        }
        return .keepRecord
    }

    public func policy(for recordType: CloudRecordType) -> ConflictPolicy {
        switch recordType {
        case .clipItem:
            return .clipItemAppendOnly
        case .pinboard:
            return .lastWriterWins(modifiedAtKey: PinboardField.modifiedAt.rawValue)
        case .pinboardMembership:
            return .lastWriterWins(modifiedAtKey: PinboardMembershipField.modifiedAt.rawValue)
        case .clipRepresentation:
            return .lastWriterWins(modifiedAtKey: ClipRepresentationField.modifiedAt.rawValue)
        case .linkPreview:
            return .lastWriterWins(modifiedAtKey: LinkPreviewField.fetchedAt.rawValue)
        }
    }

    public func resolve(local: CKRecord, remote: CKRecord) -> ConflictResolution {
        guard let recordType = remote.cloudRecordType else {
            return .keepRemote
        }

        switch policy(for: recordType) {
        case .lastWriterWins(let modifiedAtKey):
            return resolveLastWriterWins(local: local, remote: remote, modifiedAtKey: modifiedAtKey)
        case .clipItemAppendOnly:
            return resolveClipItemAppendOnly(local: local, remote: remote)
        }
    }
}

public enum ConflictPolicy: Equatable, Sendable {
    case lastWriterWins(modifiedAtKey: String)
    case clipItemAppendOnly
}

