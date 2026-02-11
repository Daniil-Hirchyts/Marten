import Foundation

/// Errors related to shared pinboard operations.
public enum PinboardSharingError: Error, LocalizedError, Sendable {
    case featureDisabled
    case cannotShareLockedPinboard
    case cannotLockSharedPinboard
    case insufficientPermission
    case ownerOnlyOperation
    case shareNotFound
    case invalidShareMetadata
    case sharedZoneSetupFailed
    case acceptShareFailed
    case fetchShareDetailsFailed
    case updateShareSettingsFailed
    case inviteParticipantFailed
    case updateParticipantPermissionFailed
    case removeParticipantFailed
    case invalidParticipantIdentifier
    case participantLookupFailed
    case stopSharingFailed
    case leaveShareFailed

    public var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Shared pinboards feature is not enabled"
        case .cannotShareLockedPinboard:
            return "Cannot share a locked pinboard"
        case .cannotLockSharedPinboard:
            return "Cannot lock a shared pinboard"
        case .insufficientPermission:
            return "You do not have permission to perform this action"
        case .ownerOnlyOperation:
            return "Only the pinboard owner can perform this action"
        case .shareNotFound:
            return "Share not found"
        case .invalidShareMetadata:
            return "Invalid share metadata"
        case .sharedZoneSetupFailed:
            return "Failed to set up shared zone"
        case .acceptShareFailed:
            return "Failed to accept share invitation"
        case .fetchShareDetailsFailed:
            return "Failed to fetch share details"
        case .updateShareSettingsFailed:
            return "Failed to update share settings"
        case .inviteParticipantFailed:
            return "Failed to invite participant"
        case .updateParticipantPermissionFailed:
            return "Failed to update participant permission"
        case .removeParticipantFailed:
            return "Failed to remove participant"
        case .invalidParticipantIdentifier:
            return "Invalid participant identifier"
        case .participantLookupFailed:
            return "Failed to look up participant"
        case .stopSharingFailed:
            return "Failed to stop sharing"
        case .leaveShareFailed:
            return "Failed to leave shared pinboard"
        }
    }
}
