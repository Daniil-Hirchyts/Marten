import Foundation

/// Rich sharing state for a pinboard, including participants and active permissions.
public struct ShareDetails: Sendable, Equatable {
    public let shareURL: URL?
    public let accessControl: ShareAccessControl
    public let defaultPermission: SharePermission
    public let isOwner: Bool
    public let participants: [ShareParticipantInfo]

    public init(
        shareURL: URL?,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission,
        isOwner: Bool,
        participants: [ShareParticipantInfo]
    ) {
        self.shareURL = shareURL
        self.accessControl = accessControl
        self.defaultPermission = defaultPermission
        self.isOwner = isOwner
        self.participants = participants
    }
}

/// Participant row information used by sharing UI.
public struct ShareParticipantInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let email: String?
    public let permission: SharePermission
    public let acceptanceStatus: ShareParticipantAcceptanceStatus
    public let isOwner: Bool
    public let isCurrentUser: Bool

    public init(
        id: String,
        displayName: String,
        email: String?,
        permission: SharePermission,
        acceptanceStatus: ShareParticipantAcceptanceStatus,
        isOwner: Bool,
        isCurrentUser: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.permission = permission
        self.acceptanceStatus = acceptanceStatus
        self.isOwner = isOwner
        self.isCurrentUser = isCurrentUser
    }
}

/// Public acceptance states mapped from CloudKit participant status.
public enum ShareParticipantAcceptanceStatus: String, Sendable, Equatable {
    case unknown
    case pending
    case accepted
    case removed
}
