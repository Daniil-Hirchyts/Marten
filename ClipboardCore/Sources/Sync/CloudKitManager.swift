import CloudKit
import Foundation

/// Protocol for CloudKit database operations, enabling testability.
public protocol CloudKitDatabaseProviding: AnyObject, Sendable {
    func save(_ zone: CKRecordZone) async throws -> CKRecordZone
    func deleteRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID
    func save(_ subscription: CKSubscription) async throws -> CKSubscription
    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID
    func recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone
}

/// Default implementation using CKDatabase.
extension CKDatabase: CloudKitDatabaseProviding {}

/// Protocol for CloudKit container operations, enabling testability.
public protocol CloudKitContainerProviding: Sendable {
    var privateCloudDatabase: CloudKitDatabaseProviding { get }
    func accountStatus() async throws -> CKAccountStatus
}

/// Wrapper to make CKContainer conform to CloudKitContainerProviding.
public final class SystemCloudKitContainer: CloudKitContainerProviding, @unchecked Sendable {
    private let container: CKContainer

    public init(identifier: String) {
        self.container = CKContainer(identifier: identifier)
    }

    public var privateCloudDatabase: CloudKitDatabaseProviding {
        container.privateCloudDatabase
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

/// Represents the current state of CloudKit account and sync.
public enum CloudKitAccountState: Equatable, Sendable {
    case unknown
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
}

/// Protocol for observing CloudKit manager state changes.
public protocol CloudKitManagerDelegate: AnyObject {
    func cloudKitManager(_ manager: CloudKitManager, didChangeAccountState state: CloudKitAccountState)
    func cloudKitManager(_ manager: CloudKitManager, didEncounterError error: CloudKitSyncError)
    func cloudKitManager(_ manager: CloudKitManager, didCompleteZoneSetup success: Bool)
}

/// Manages CloudKit container initialization, zone setup, and subscriptions.
///
/// This class handles:
/// - CloudKit container and database access
/// - Custom zone creation and management
/// - Zone subscription setup for remote notifications
/// - Account status monitoring
public final class CloudKitManager {
    // MARK: - Properties

    private let container: CloudKitContainerProviding
    private let configuration: CloudKitConfiguration
    private let tokenManager: SyncTokenManager

    /// The private database for sync operations.
    public var privateDatabase: CloudKitDatabaseProviding {
        container.privateCloudDatabase
    }

    /// The custom zone ID for clipboard data.
    public let zoneID: CKRecordZone.ID

    /// The subscription ID for zone changes.
    public let subscriptionID: CKSubscription.ID

    /// Current account state.
    public private(set) var accountState: CloudKitAccountState = .unknown

    /// Whether the custom zone has been set up.
    public private(set) var isZoneSetUp: Bool = false

    /// Whether the subscription has been set up.
    public private(set) var isSubscriptionSetUp: Bool = false

    /// Delegate for state change notifications.
    public weak var delegate: CloudKitManagerDelegate?

    /// Lock for thread-safe state updates.
    private let stateLock = NSLock()

    // MARK: - Initialization

    /// Creates a new CloudKitManager with the specified configuration.
    ///
    /// - Parameters:
    ///   - configuration: The CloudKit configuration to use.
    ///   - container: The CloudKit container provider (defaults to system container).
    ///   - tokenManager: The sync token manager for change tracking.
    public init(
        configuration: CloudKitConfiguration = .default,
        container: CloudKitContainerProviding? = nil,
        tokenManager: SyncTokenManager = SyncTokenManager()
    ) {
        self.configuration = configuration
        self.container = container ?? SystemCloudKitContainer(identifier: configuration.containerIdentifier)
        self.tokenManager = tokenManager

        self.zoneID = CKRecordZone.ID(
            zoneName: configuration.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        self.subscriptionID = "clipboard-zone-subscription"
    }

    // MARK: - Account Status

    /// Checks the current iCloud account status.
    ///
    /// - Returns: The current account state.
    /// - Throws: `CloudKitSyncError` if the status cannot be determined.
    @discardableResult
    public func checkAccountStatus() async throws -> CloudKitAccountState {
        updateAccountState(.checking)

        do {
            let status = try await container.accountStatus()
            let newState = mapAccountStatus(status)
            updateAccountState(newState)

            guard newState == .available else {
                throw errorForAccountState(newState)
            }

            return newState
        } catch let error as CloudKitSyncError {
            throw error
        } catch {
            updateAccountState(.unknown)
            throw CloudKitSyncError.unexpected(error)
        }
    }

    /// Verifies the account is available for sync operations.
    ///
    /// - Throws: `CloudKitSyncError` if the account is not available.
    public func verifyAccountAvailable() async throws {
        let state = try await checkAccountStatus()
        guard state == .available else {
            throw errorForAccountState(state)
        }
    }

    // MARK: - Zone Setup

    /// Sets up the custom zone for clipboard data.
    ///
    /// This creates a custom zone in the private database if it doesn't exist.
    /// Custom zones are required for advanced features like change tracking.
    ///
    /// - Throws: `CloudKitSyncError` if zone creation fails.
    public func setupZone() async throws {
        try await verifyAccountAvailable()

        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await privateDatabase.save(zone)
            setZoneSetUp(true)
            delegate?.cloudKitManager(self, didCompleteZoneSetup: true)
        } catch let error as CKError {
            let syncError = handleZoneSetupError(error)
            delegate?.cloudKitManager(self, didEncounterError: syncError)
            throw syncError
        } catch {
            let syncError = CloudKitSyncError.zoneCreationFailed(error)
            delegate?.cloudKitManager(self, didEncounterError: syncError)
            throw syncError
        }
    }

    /// Deletes the custom zone and all its records.
    ///
    /// - Warning: This will delete all synced data. Use with caution.
    /// - Throws: `CloudKitSyncError` if deletion fails.
    public func deleteZone() async throws {
        do {
            _ = try await privateDatabase.deleteRecordZone(withID: zoneID)
            setZoneSetUp(false)
            try tokenManager.clearToken(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            setZoneSetUp(false)
            try tokenManager.clearToken(for: zoneID)
        } catch {
            throw CloudKitSyncError.unexpected(error)
        }
    }

    // MARK: - Subscription Setup

    /// Sets up a subscription to receive notifications about zone changes.
    ///
    /// This enables the app to receive silent push notifications when
    /// data changes on other devices.
    ///
    /// - Throws: `CloudKitSyncError` if subscription setup fails.
    public func setupSubscription() async throws {
        try await verifyAccountAvailable()

        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await privateDatabase.save(subscription)
            setSubscriptionSetUp(true)
        } catch let error as CKError {
            let syncError = handleSubscriptionSetupError(error)
            delegate?.cloudKitManager(self, didEncounterError: syncError)
            throw syncError
        } catch {
            let syncError = CloudKitSyncError.subscriptionSetupFailed(error)
            delegate?.cloudKitManager(self, didEncounterError: syncError)
            throw syncError
        }
    }

    /// Deletes the zone subscription.
    ///
    /// - Throws: `CloudKitSyncError` if deletion fails.
    public func deleteSubscription() async throws {
        do {
            _ = try await privateDatabase.deleteSubscription(withID: subscriptionID)
            setSubscriptionSetUp(false)
        } catch let error as CKError where error.code == .unknownItem {
            setSubscriptionSetUp(false)
        } catch {
            throw CloudKitSyncError.unexpected(error)
        }
    }

    // MARK: - Complete Setup

    /// Performs complete CloudKit setup: account check, zone creation, and subscription.
    ///
    /// This is the recommended entry point for initializing CloudKit sync.
    ///
    /// - Throws: `CloudKitSyncError` if any step fails.
    public func performCompleteSetup() async throws {
        try await checkAccountStatus()
        try await setupZone()
        try await setupSubscription()
    }

    // MARK: - Zone Verification

    /// Verifies the zone exists and is accessible.
    ///
    /// - Returns: `true` if the zone exists, `false` otherwise.
    public func verifyZoneExists() async throws -> Bool {
        do {
            _ = try await privateDatabase.recordZone(for: zoneID)
            setZoneSetUp(true)
            return true
        } catch let error as CKError where error.code == .zoneNotFound {
            setZoneSetUp(false)
            return false
        } catch {
            throw CloudKitSyncError.unexpected(error)
        }
    }

    // MARK: - Token Management

    /// Gets the current server change token for the zone.
    ///
    /// - Returns: The stored change token, or `nil` for initial sync.
    public func getZoneChangeToken() throws -> CKServerChangeToken? {
        try tokenManager.loadToken(for: zoneID)
    }

    /// Saves a new server change token for the zone.
    ///
    /// - Parameter token: The token to save.
    public func saveZoneChangeToken(_ token: CKServerChangeToken) throws {
        try tokenManager.saveToken(token, for: zoneID)
    }

    /// Clears the zone change token, forcing a full re-sync.
    public func clearZoneChangeToken() throws {
        try tokenManager.clearToken(for: zoneID)
    }

    // MARK: - Private Helpers

    private func updateAccountState(_ newState: CloudKitAccountState) {
        stateLock.lock()
        let oldState = accountState
        accountState = newState
        stateLock.unlock()

        if oldState != newState {
            delegate?.cloudKitManager(self, didChangeAccountState: newState)
        }
    }

    private func setZoneSetUp(_ value: Bool) {
        stateLock.lock()
        isZoneSetUp = value
        stateLock.unlock()
    }

    private func setSubscriptionSetUp(_ value: Bool) {
        stateLock.lock()
        isSubscriptionSetUp = value
        stateLock.unlock()
    }

    private func mapAccountStatus(_ status: CKAccountStatus) -> CloudKitAccountState {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .unknown
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .unknown
        }
    }

    private func errorForAccountState(_ state: CloudKitAccountState) -> CloudKitSyncError {
        switch state {
        case .noAccount:
            return .notSignedIn
        case .restricted:
            return .accountRestricted
        case .temporarilyUnavailable:
            return .networkUnavailable
        case .unknown, .checking:
            return .accountStatusUnknown
        case .available:
            fatalError("Should not create error for available state")
        }
    }

    private func handleZoneSetupError(_ error: CKError) -> CloudKitSyncError {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated:
            updateAccountState(.noAccount)
            return .notSignedIn
        case .quotaExceeded:
            return .quotaExceeded
        default:
            return .zoneCreationFailed(error)
        }
    }

    private func handleSubscriptionSetupError(_ error: CKError) -> CloudKitSyncError {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated:
            updateAccountState(.noAccount)
            return .notSignedIn
        default:
            return .subscriptionSetupFailed(error)
        }
    }
}

extension CloudKitManager: @unchecked Sendable {}
