import CloudKit
import Foundation

/// Errors that can occur while preparing records before CloudKit upload.
public enum SyncRecordPreparationError: Error, LocalizedError, Sendable {
    case assetAttachmentFailed(engine: String, representationID: UUID, reason: String)

    public var errorDescription: String? {
        switch self {
        case .assetAttachmentFailed(let engine, let representationID, let reason):
            return
                "\(engine) failed to attach asset for representation \(representationID.uuidString): \(reason)"
        }
    }
}

/// Errors that can occur during CloudKit sync operations.
public enum CloudKitSyncError: Error, LocalizedError, Sendable {
    /// The CloudKit container is not available.
    case containerNotAvailable

    /// The user is not signed into iCloud.
    case notSignedIn

    /// iCloud account is restricted (e.g., parental controls).
    case accountRestricted

    /// iCloud account status could not be determined.
    case accountStatusUnknown

    /// Failed to create the custom zone.
    case zoneCreationFailed(Error)

    /// Failed to set up zone subscription.
    case subscriptionSetupFailed(Error)

    /// Network is unavailable.
    case networkUnavailable

    /// iCloud quota has been exceeded.
    case quotaExceeded

    /// A conflict occurred with a record on the server.
    case recordConflict(serverRecord: CKRecord)

    /// Failed to fetch changes from the server.
    case fetchChangesFailed(Error)

    /// Failed to push changes to the server.
    case pushChangesFailed(Error)

    /// The zone was not found (may have been deleted).
    case zoneNotFound

    /// The user deleted the zone; a full re-sync is required.
    case userDeletedZone

    /// A partial failure occurred during batch operations.
    case partialFailure(errors: [CKRecord.ID: Error])

    /// Server rejected the request due to invalid arguments.
    case serverRejected(reason: String)

    /// An unexpected error occurred.
    case unexpected(Error)

    public var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "CloudKit container is not available."
        case .notSignedIn:
            return "Please sign in to iCloud to enable sync."
        case .accountRestricted:
            return "iCloud account is restricted."
        case .accountStatusUnknown:
            return "Could not determine iCloud account status."
        case .zoneCreationFailed(let error):
            return "Failed to create sync zone: \(error.localizedDescription)"
        case .subscriptionSetupFailed(let error):
            return "Failed to set up sync subscription: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network is unavailable. Sync will resume when connected."
        case .quotaExceeded:
            return "iCloud storage quota exceeded."
        case .recordConflict:
            return "A sync conflict occurred."
        case .fetchChangesFailed(let error):
            return "Failed to fetch changes: \(error.localizedDescription)"
        case .pushChangesFailed(let error):
            return "Failed to push changes: \(error.localizedDescription)"
        case .zoneNotFound:
            return "Sync zone not found."
        case .userDeletedZone:
            return "Sync data was reset. Re-syncing all items."
        case .partialFailure:
            return "Some items failed to sync."
        case .serverRejected(let reason):
            return "Server rejected request: \(reason)"
        case .unexpected(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }

    /// Whether this error is recoverable with a retry.
    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .fetchChangesFailed, .pushChangesFailed:
            return true
        case .partialFailure:
            return true
        case .zoneNotFound, .userDeletedZone:
            return true
        default:
            return false
        }
    }

    /// Whether this error requires user action to resolve.
    public var requiresUserAction: Bool {
        switch self {
        case .notSignedIn, .accountRestricted, .quotaExceeded:
            return true
        default:
            return false
        }
    }
}

/// Errors that can occur during sync token management.
public enum SyncTokenError: Error, LocalizedError, Sendable {
    /// The token was not found for the specified zone.
    case tokenNotFound(zoneID: String)

    /// The token data is corrupted or invalid.
    case invalidTokenFormat

    /// Failed to persist the token.
    case persistenceFailed(Error)

    /// Failed to decode the token.
    case decodingFailed(Error)

    /// The zone ID is invalid.
    case invalidZoneID

    public var errorDescription: String? {
        switch self {
        case .tokenNotFound(let zoneID):
            return "Sync token not found for zone: \(zoneID)"
        case .invalidTokenFormat:
            return "Sync token format is invalid."
        case .persistenceFailed(let error):
            return "Failed to save sync token: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode sync token: \(error.localizedDescription)"
        case .invalidZoneID:
            return "Invalid zone identifier."
        }
    }
}

/// Provides helper methods for categorizing CloudKit errors.
public enum CloudKitErrorClassifier {

    /// Classifies a CKError into a CloudKitSyncError.
    public static func classify(_ error: Error) -> CloudKitSyncError {
        guard let ckError = error as? CKError else {
            return .unexpected(error)
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable

        case .notAuthenticated:
            return .notSignedIn

        case .quotaExceeded:
            return .quotaExceeded

        case .zoneNotFound:
            return .zoneNotFound

        case .userDeletedZone:
            return .userDeletedZone

        case .serverRecordChanged:
            if let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                return .recordConflict(serverRecord: serverRecord)
            }
            return .unexpected(error)

        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                return .partialFailure(errors: partialErrors)
            }
            return .unexpected(error)

        case .invalidArguments:
            return .serverRejected(reason: ckError.localizedDescription)

        case .serverRejectedRequest:
            return .serverRejected(reason: ckError.localizedDescription)

        default:
            return .unexpected(error)
        }
    }

    /// Determines if the error is transient and should be retried.
    public static func isTransient(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else {
            return false
        }

        switch ckError.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy:
            return true
        default:
            return false
        }
    }

    /// Returns the suggested retry delay from a CKError, if available.
    public static func retryAfterDelay(for error: Error) -> TimeInterval? {
        guard let ckError = error as? CKError else {
            return nil
        }
        return ckError.retryAfterSeconds
    }
}
