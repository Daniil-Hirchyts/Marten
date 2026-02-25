import CloudKit
import Combine
import CoreData
import Foundation
import os.log

// MARK: - Sync Transaction Authors

/// Constants for Core Data transaction authors used to prevent sync feedback loops.
public enum SyncTransactionAuthor {
    public static let privateInbound = "private-inbound-sync"
    public static let sharedInbound = "shared-inbound-sync"

    /// Returns `true` when the given author identifies an inbound sync save
    /// that outbound engines should ignore.
    public static func isInboundSync(_ author: String?) -> Bool {
        guard let author else { return false }
        return author == privateInbound || author == sharedInbound
    }
}

// MARK: - Sync Status

/// Represents the current synchronization status.
public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case synced
    case error(CloudKitSyncError)

    public static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.synced, .synced):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }
}

// MARK: - Sync Progress

/// Tracks the progress of sync operations.
public struct SyncProgress: Equatable, Sendable {
    public let itemsQueued: Int
    public let itemsUploaded: Int
    public let itemsDownloaded: Int

    public init(itemsQueued: Int = 0, itemsUploaded: Int = 0, itemsDownloaded: Int = 0) {
        self.itemsQueued = itemsQueued
        self.itemsUploaded = itemsUploaded
        self.itemsDownloaded = itemsDownloaded
    }

    public static let zero = SyncProgress()
}

// MARK: - Sync Coordinator Protocol

/// Protocol for SyncCoordinator to enable testability.
@MainActor
public protocol SyncCoordinating: AnyObject {
    var status: SyncStatus { get }
    var lastSyncDate: Date? { get }
    var progress: SyncProgress { get }
    var syncEnabled: Bool { get set }

    func startSync() async throws
    func stopSync()
    func triggerSyncNow() async throws
    func handlePushNotification() async
    func acceptShare(metadata: CKShare.Metadata) async throws
    func syncSharedNow() async throws
}

// MARK: - Sync Coordinator Delegate

/// Delegate protocol for sync coordinator events.
public protocol SyncCoordinatorDelegate: AnyObject {
    func syncCoordinator(_ coordinator: SyncCoordinator, didChangeStatus status: SyncStatus)
    func syncCoordinator(_ coordinator: SyncCoordinator, didEncounterError error: CloudKitSyncError)
    func syncCoordinator(_ coordinator: SyncCoordinator, didCompleteSync result: SyncResult)
}

/// Result of a complete sync cycle.
public struct SyncResult: Sendable {
    public let uploadedCount: Int
    public let downloadedCount: Int
    public let deletedCount: Int
    public let duration: TimeInterval

    public init(uploadedCount: Int, downloadedCount: Int, deletedCount: Int, duration: TimeInterval) {
        self.uploadedCount = uploadedCount
        self.downloadedCount = downloadedCount
        self.deletedCount = deletedCount
        self.duration = duration
    }
}

// MARK: - Sync Coordinator Configuration

/// Configuration for SyncCoordinator behavior.
public struct SyncCoordinatorConfiguration: Sendable {
    /// Interval for periodic inbound sync when app is active (default: 30 seconds).
    public var periodicFetchInterval: TimeInterval

    /// When true, the first periodic inbound sync fires immediately instead of waiting
    /// for the full `periodicFetchInterval`. Useful on watchOS where the app may only
    /// be active for a few seconds.
    public var performImmediateInboundSync: Bool

    /// UserDefaults key for sync enabled preference.
    public var syncEnabledKey: String

    /// UserDefaults key for last sync date.
    public var lastSyncDateKey: String

    public static let `default` = SyncCoordinatorConfiguration(
        periodicFetchInterval: 30.0,
        performImmediateInboundSync: false,
        syncEnabledKey: "com.hirchyts.marten.syncEnabled",
        lastSyncDateKey: "com.hirchyts.marten.lastSyncDate"
    )

    public init(
        periodicFetchInterval: TimeInterval = 30.0,
        performImmediateInboundSync: Bool = false,
        syncEnabledKey: String = "com.hirchyts.marten.syncEnabled",
        lastSyncDateKey: String = "com.hirchyts.marten.lastSyncDate"
    ) {
        self.periodicFetchInterval = periodicFetchInterval
        self.performImmediateInboundSync = performImmediateInboundSync
        self.syncEnabledKey = syncEnabledKey
        self.lastSyncDateKey = lastSyncDateKey
    }
}

// MARK: - Sync Coordinator

/// Coordinates all sync components for bidirectional CloudKit synchronization.
///
/// SyncCoordinator integrates CloudKitManager, OutboundSyncEngine, InboundSyncEngine,
/// and AssetSyncManager to provide a unified sync experience with status reporting.
@MainActor
public final class SyncCoordinator: ObservableObject, SyncCoordinating {

    // MARK: - Published Properties

    /// Current sync status.
    @Published public private(set) var status: SyncStatus = .idle

    /// Timestamp of last successful sync.
    @Published public private(set) var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                userDefaults.set(date, forKey: configuration.lastSyncDateKey)
            }
        }
    }

    /// Current sync progress.
    @Published public private(set) var progress: SyncProgress = .zero

    /// Whether sync is enabled.
    @Published public var syncEnabled: Bool {
        didSet {
            userDefaults.set(syncEnabled, forKey: configuration.syncEnabledKey)
            handleSyncEnabledChange()
        }
    }

    // MARK: - Combine Publishers

    /// Publisher for sync status changes.
    public var statusPublisher: AnyPublisher<SyncStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    /// Publisher for sync progress updates.
    public var progressPublisher: AnyPublisher<SyncProgress, Never> {
        $progress.eraseToAnyPublisher()
    }

    /// Publisher for sync errors.
    public var errorPublisher: AnyPublisher<CloudKitSyncError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    /// Fires after every completed inbound sync (periodic, push, or manual).
    public var syncCompletedPublisher: AnyPublisher<Void, Never> {
        syncCompletedSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let cloudKitManager: CloudKitManager
    private let outboundEngine: OutboundSyncEngine
    private let inboundEngine: InboundSyncEngine
    private let assetSyncManager: AssetSyncManager
    private let persistenceController: PersistenceController
    private let configuration: SyncCoordinatorConfiguration
    private let userDefaults: UserDefaults

    // Shared pinboard sync infrastructure (nil when feature flag is off)
    private let shareCoordinator: ShareCoordinator?
    private let sharedInboundEngine: SharedInboundSyncEngine?
    private let sharedOutboundEngine: SharedOutboundSyncEngine?

    // MARK: - Private State

    private let periodicScheduler = PeriodicSyncScheduler()
    private var stateMachine = SyncStateMachine()
    private var isSyncInProgress = false
    private var cancellables = Set<AnyCancellable>()
    private let errorSubject = PassthroughSubject<CloudKitSyncError, Never>()
    private let syncCompletedSubject = PassthroughSubject<Void, Never>()
    private var isSetUp = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hirchyts.marten",
        category: "SyncCoordinator"
    )
    private static let membershipBackfillCompletedKey = "com.hirchyts.marten.sync.membershipBackfill.completed"

    // MARK: - Initialization

    /// Creates a new SyncCoordinator with the specified dependencies.
    ///
    /// - Parameters:
    ///   - cloudKitManager: The CloudKit manager for account and zone setup.
    ///   - outboundEngine: The engine for pushing local changes.
    ///   - inboundEngine: The engine for pulling remote changes.
    ///   - assetSyncManager: The manager for asset synchronization.
    ///   - persistenceController: The Core Data persistence controller.
    ///   - configuration: Configuration options for the coordinator.
    ///   - userDefaults: UserDefaults for persisting preferences.
    public init(
        cloudKitManager: CloudKitManager,
        outboundEngine: OutboundSyncEngine,
        inboundEngine: InboundSyncEngine,
        assetSyncManager: AssetSyncManager,
        persistenceController: PersistenceController,
        configuration: SyncCoordinatorConfiguration = .default,
        userDefaults: UserDefaults = .standard,
        shareCoordinator: ShareCoordinator? = nil,
        sharedInboundEngine: SharedInboundSyncEngine? = nil,
        sharedOutboundEngine: SharedOutboundSyncEngine? = nil
    ) {
        self.cloudKitManager = cloudKitManager
        self.outboundEngine = outboundEngine
        self.inboundEngine = inboundEngine
        self.assetSyncManager = assetSyncManager
        self.persistenceController = persistenceController
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.shareCoordinator = shareCoordinator
        self.sharedInboundEngine = sharedInboundEngine
        self.sharedOutboundEngine = sharedOutboundEngine
        self.syncEnabled = userDefaults.bool(forKey: configuration.syncEnabledKey)
        self.lastSyncDate = userDefaults.object(forKey: configuration.lastSyncDateKey) as? Date

        setupObservers()
    }

    deinit {
        periodicScheduler.stop()
    }

    // MARK: - Public Methods

    /// Starts sync operations.
    ///
    /// This method:
    /// 1. Verifies iCloud account is available
    /// 2. Sets up CloudKit zone and subscription
    /// 3. Starts outbound sync engine
    /// 4. Schedules periodic inbound sync
    ///
    /// - Throws: `CloudKitSyncError` if setup fails.
    public func startSync() async throws {
        guard syncEnabled else {
            log("Sync not enabled, skipping start")
            return
        }

        guard !isSetUp else {
            log("Sync already started")
            return
        }

        log("Starting sync...")
        updateStatus(.syncing)

        do {
            // Verify account and set up CloudKit.
            // If subscription creation is transiently cancelled, continue with periodic sync.
            do {
                try await cloudKitManager.performCompleteSetup()
                log("CloudKit setup complete")
            } catch let error as CloudKitSyncError where shouldContinueWithoutSubscription(error) {
                log("CloudKit subscription setup failed transiently (\(error.localizedDescription)); continuing without push subscription")
            }

            // Start outbound engine (monitors Core Data saves)
            outboundEngine.start()
            log("Outbound engine started")

            await performMembershipBackfillIfNeeded()

            // Start shared sync engines when feature flag is enabled
            if SharedPinboardsFeatureFlag.isEnabled, sharedOutboundEngine != nil {
                sharedOutboundEngine?.start()
                try? await cloudKitManager.setupSharedDatabaseSubscription()
                log("Shared sync engines started")
            }

            // Start periodic inbound sync
            startPeriodicInboundSync()

            isSetUp = true
            updateStatus(.synced)
            log("Sync started successfully")
        } catch let error as CloudKitSyncError {
            handleError(error)
            throw error
        } catch {
            let syncError = CloudKitSyncError.unexpected(error)
            handleError(syncError)
            throw syncError
        }
    }

    /// Stops all sync operations.
    public func stopSync() {
        log("Stopping sync...")

        // Stop periodic sync
        periodicScheduler.stop()

        // Stop outbound engine
        outboundEngine.stop()

        // Stop shared engines
        sharedOutboundEngine?.stop()

        isSetUp = false
        updateStatus(.idle)
        log("Sync stopped")
    }

    /// Triggers an immediate sync cycle.
    ///
    /// This method:
    /// 1. Flushes outbound changes
    /// 2. Fetches inbound changes
    /// 3. Coordinates asset sync
    ///
    /// - Throws: `CloudKitSyncError` if sync fails.
    public func triggerSyncNow() async throws {
        guard syncEnabled else {
            throw CloudKitSyncError.containerNotAvailable
        }

        guard acquireSyncLock() else {
            log("Sync already in progress, skipping manual trigger")
            return
        }

        defer { releaseSyncLock() }

        log("Manual sync triggered")
        let startTime = Date()
        updateStatus(.syncing)

        do {
            // Flush outbound changes and wait for completion
            await outboundEngine.flushAndAwait()

            // Perform inbound sync
            let result = try await inboundEngine.syncInbound()

            let duration = Date().timeIntervalSince(startTime)
            let syncResult = SyncResult(
                uploadedCount: 0,
                downloadedCount: result.fetchedRecordCount,
                deletedCount: result.deletedRecordCount,
                duration: duration
            )

            updateProgress(SyncProgress(
                itemsQueued: 0,
                itemsUploaded: 0,
                itemsDownloaded: result.fetchedRecordCount
            ))

            lastSyncDate = Date()
            updateStatus(.synced)
            syncCompletedSubject.send()

            log("Manual sync completed: \(syncResult.downloadedCount) downloaded, \(syncResult.deletedCount) deleted in \(String(format: "%.2f", duration))s")
        } catch let error as CloudKitSyncError {
            handleError(error)
            throw error
        } catch {
            let syncError = CloudKitSyncError.unexpected(error)
            handleError(syncError)
            throw syncError
        }
    }

    /// Handles a push notification for remote changes.
    ///
    /// This triggers an immediate inbound sync to fetch the latest changes.
    public func handlePushNotification() async {
        guard syncEnabled, isSetUp else {
            log("Ignoring push notification - sync not enabled or not set up")
            return
        }

        log("Push notification received, triggering inbound sync")

        guard acquireSyncLock() else {
            log("Sync already in progress, skipping push-triggered sync")
            return
        }

        defer { releaseSyncLock() }

        do {
            updateStatus(.syncing)
            let result = try await inboundEngine.syncInbound()

            // Also trigger shared inbound sync when feature flag is enabled
            if SharedPinboardsFeatureFlag.isEnabled, let sharedInbound = sharedInboundEngine {
                let sharedZoneIDs = fetchSharedZoneIDs()
                if !sharedZoneIDs.isEmpty {
                    let sharedResult = try await sharedInbound.syncInbound(zoneIDs: sharedZoneIDs)
                    log("Push-triggered shared sync: \(sharedResult.fetchedRecordCount) fetched")
                }
            }

            updateProgress(SyncProgress(
                itemsQueued: 0,
                itemsUploaded: 0,
                itemsDownloaded: result.fetchedRecordCount
            ))

            lastSyncDate = Date()
            updateStatus(.synced)
            syncCompletedSubject.send()

            log("Push-triggered sync completed: \(result.fetchedRecordCount) fetched")
        } catch {
            log("Push-triggered sync failed: \(error.localizedDescription)")
            if let syncError = error as? CloudKitSyncError {
                handleError(syncError)
            }
        }
    }

    // MARK: - Shared Pinboard Operations

    /// Accepts a CloudKit share invitation.
    ///
    /// Delegates to ShareCoordinator to accept the share and persist metadata,
    /// then triggers an immediate shared inbound sync.
    ///
    /// - Parameter metadata: The share metadata from the system callback.
    public func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let coordinator = shareCoordinator else {
            let error = PinboardSharingError.featureDisabled
            log("acceptShare failed: shared infrastructure not available (\(error.localizedDescription))")
            throw error
        }

        log("Accepting share invitation")
        try await coordinator.acceptShare(metadata: metadata)

        // Trigger shared inbound sync to pull the shared data
        do {
            try await syncSharedNow()
            log("Share accepted and synced")
        } catch {
            log("Share accepted but shared sync failed: \(String(describing: error))")
        }
    }

    /// Triggers an immediate sync for shared data only.
    ///
    /// Fetches all known shared zone IDs from local ShareMetadata and
    /// syncs each zone via SharedInboundSyncEngine.
    public func syncSharedNow() async throws {
        guard let sharedInbound = sharedInboundEngine else {
            let error = PinboardSharingError.featureDisabled
            log("syncSharedNow failed: shared inbound engine not available (\(error.localizedDescription))")
            throw error
        }

        let sharedZoneIDs = fetchSharedZoneIDs()
        guard !sharedZoneIDs.isEmpty else {
            log("No shared zones to sync")
            return
        }

        log("Syncing \(sharedZoneIDs.count) shared zone(s)")
        let result = try await sharedInbound.syncInbound(zoneIDs: sharedZoneIDs)
        log("Shared sync completed: \(result.fetchedRecordCount) fetched, \(result.deletedRecordCount) deleted")
    }

    // MARK: - App Lifecycle

    /// Called when the app enters the foreground.
    public func handleAppDidBecomeActive() {
        guard syncEnabled, isSetUp else { return }

        log("App became active, resuming periodic sync")
        startPeriodicInboundSync()
    }

    /// Called when the app enters the background.
    public func handleAppWillResignActive() {
        log("App will resign active, pausing periodic sync")
        periodicScheduler.stop()
    }

    /// Called when network becomes available.
    public func handleNetworkBecameAvailable() {
        guard syncEnabled else { return }

        log("Network became available")

        Task {
            if !isSetUp {
                try? await startSync()
            } else {
                try? await triggerSyncNow()
            }
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe asset sync progress
        assetSyncManager.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progressUpdate in
                self?.log("Asset progress: \(progressUpdate.recordName) - \(Int(progressUpdate.fractionCompleted * 100))%")
            }
            .store(in: &cancellables)
    }

    private func performMembershipBackfillIfNeeded() async {
        guard userDefaults.bool(forKey: Self.membershipBackfillCompletedKey) == false else { return }

        await outboundEngine.enqueueMembershipBackfillForAllItems()
        userDefaults.set(true, forKey: Self.membershipBackfillCompletedKey)
        log("Queued one-time pinboard membership backfill")
    }

    private func handleSyncEnabledChange() {
        if syncEnabled {
            Task {
                try? await startSync()
            }
        } else {
            stopSync()
        }
    }

    private func startPeriodicInboundSync() {
        periodicScheduler.start(interval: configuration.periodicFetchInterval, runImmediately: configuration.performImmediateInboundSync) { [weak self] in
            let coordinator = self
            await MainActor.run { [coordinator] in
                guard let coordinator else { return }
                guard coordinator.syncEnabled, coordinator.isSetUp else { return }

                Task { [weak coordinator] in
                    guard let coordinator else { return }
                    await coordinator.performPeriodicInboundSync()
                }
            }
        }
    }

    private func performPeriodicInboundSync() async {
        guard acquireSyncLock() else {
            log("Skipping periodic sync - sync in progress")
            return
        }

        defer { releaseSyncLock() }

        log("Performing periodic inbound sync")

        do {
            updateStatus(.syncing)
            let result = try await inboundEngine.syncInbound()

            if result.fetchedRecordCount > 0 || result.deletedRecordCount > 0 {
                updateProgress(SyncProgress(
                    itemsQueued: 0,
                    itemsUploaded: 0,
                    itemsDownloaded: result.fetchedRecordCount
                ))
                log("Periodic sync: \(result.fetchedRecordCount) fetched, \(result.deletedRecordCount) deleted")
            }

            lastSyncDate = Date()
            updateStatus(.synced)
            syncCompletedSubject.send()
        } catch {
            log("Periodic sync failed: \(error.localizedDescription)")
            if let syncError = error as? CloudKitSyncError {
                handleError(syncError)
            }
        }
    }

    private func updateStatus(_ newStatus: SyncStatus) {
        stateMachine.transition(to: newStatus)
        status = stateMachine.status
    }

    private func updateProgress(_ newProgress: SyncProgress) {
        stateMachine.updateProgress(newProgress)
        progress = stateMachine.progress
    }

    private func handleError(_ error: CloudKitSyncError) {
        log("Sync error: \(error.localizedDescription)")
        updateStatus(.error(error))
        errorSubject.send(error)
    }

    private func acquireSyncLock() -> Bool {
        guard !isSyncInProgress else { return false }
        isSyncInProgress = true
        return true
    }

    private func releaseSyncLock() {
        isSyncInProgress = false
    }

    /// Fetches all shared zone IDs from local ShareMetadata.
    private func fetchSharedZoneIDs() -> [CKRecordZone.ID] {
        let context = persistenceController.newBackgroundContext()
        var zoneIDs: [CKRecordZone.ID] = []

        context.performAndWait {
            let request = ShareMetadata.fetchRequest()
            guard let results = try? context.fetch(request) else { return }

            for meta in results {
                let zoneID = CKRecordZone.ID(
                    zoneName: meta.zoneName,
                    ownerName: meta.isOwner ? CKCurrentUserDefaultName : meta.zoneOwnerName
                )
                if !zoneIDs.contains(zoneID) {
                    zoneIDs.append(zoneID)
                }
            }
        }

        return zoneIDs
    }

    private func shouldContinueWithoutSubscription(_ error: CloudKitSyncError) -> Bool {
        guard case .subscriptionSetupFailed(let underlyingError) = error else {
            return false
        }

        if let ckError = underlyingError as? CKError {
            switch ckError.code {
            case .operationCancelled, .serviceUnavailable, .networkFailure, .networkUnavailable, .requestRateLimited, .zoneBusy:
                return true
            default:
                break
            }
        }

        let nsError = underlyingError as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 4097 || nsError.code == 4099 {
            return true
        }

        return false
    }

    private func log(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
    }
}

// MARK: - Factory Method

extension SyncCoordinator {
    /// Creates a SyncCoordinator with default configuration using the provided CloudKit configuration.
    ///
    /// - Parameters:
    ///   - cloudKitConfiguration: The CloudKit configuration.
    ///   - persistenceController: The Core Data persistence controller.
    ///   - userDefaults: UserDefaults for preferences.
    ///   - syncEnabledProvider: A closure that returns whether sync is enabled.
    /// - Returns: A configured SyncCoordinator instance.
    public static func create(
        cloudKitConfiguration: CloudKitConfiguration = .default,
        persistenceController: PersistenceController,
        userDefaults: UserDefaults = .standard,
        configuration: SyncCoordinatorConfiguration = .default,
        syncEnabledProvider: @escaping @Sendable () -> Bool
    ) -> SyncCoordinator {
        let tokenManager = SyncTokenManager()
        let cloudKitManager = CloudKitManager(
            configuration: cloudKitConfiguration,
            tokenManager: tokenManager
        )

        let zoneID = CKRecordZone.ID(
            zoneName: cloudKitConfiguration.zoneName,
            ownerName: CKCurrentUserDefaultName
        )

        let container = CKContainer(identifier: cloudKitConfiguration.containerIdentifier)
        let database = container.privateCloudDatabase

        let outboundEngine = OutboundSyncEngine(
            persistenceController: persistenceController,
            database: database,
            zoneID: zoneID,
            configuration: OutboundSyncEngine.Configuration(
                debounceInterval: cloudKitConfiguration.syncTiming.batchInterval,
                retryBackoff: cloudKitConfiguration.syncTiming.retryBackoff,
                maxRetries: cloudKitConfiguration.syncTiming.maxRetries
            ),
            isSyncEnabled: syncEnabledProvider
        )

        let tokenStore = SyncTokenZoneStore(tokenManager: tokenManager, zoneID: zoneID)
        let changesFetcher = CloudKitZoneChangesFetcher(database: database)
        let recordMapper = CloudRecordMapper(zoneID: zoneID)

        let inboundEngine = InboundSyncEngine(
            zoneID: zoneID,
            changesFetcher: changesFetcher,
            tokenStore: tokenStore,
            persistenceController: persistenceController,
            recordMapper: recordMapper
        )

        let assetSyncManager = AssetSyncManager()

        // Conditionally build shared sync infrastructure
        var shareCoord: ShareCoordinator?
        var sharedInbound: SharedInboundSyncEngine?
        var sharedOutbound: SharedOutboundSyncEngine?

        if SharedPinboardsFeatureFlag.isEnabled {
            let shareZoneRegistry = ShareZoneRegistry(privateZoneID: zoneID)

            shareCoord = ShareCoordinator(
                cloudKitManager: cloudKitManager,
                persistenceController: persistenceController,
                recordMapper: recordMapper
            )

            let sharedDatabase = container.sharedCloudDatabase
            let sharedChangesFetcher = CloudKitZoneChangesFetcher(
                database: sharedDatabase
            )

            sharedInbound = SharedInboundSyncEngine(
                changesFetcher: sharedChangesFetcher,
                tokenManager: tokenManager,
                persistenceController: persistenceController,
                recordMapper: recordMapper
            )

            sharedOutbound = SharedOutboundSyncEngine(
                persistenceController: persistenceController,
                privateDatabase: database,
                sharedDatabase: sharedDatabase,
                shareZoneRegistry: shareZoneRegistry,
                recordMapper: recordMapper,
                isSyncEnabled: syncEnabledProvider
            )
        }

        return SyncCoordinator(
            cloudKitManager: cloudKitManager,
            outboundEngine: outboundEngine,
            inboundEngine: inboundEngine,
            assetSyncManager: assetSyncManager,
            persistenceController: persistenceController,
            configuration: configuration,
            userDefaults: userDefaults,
            shareCoordinator: shareCoord,
            sharedInboundEngine: sharedInbound,
            sharedOutboundEngine: sharedOutbound
        )
    }
}
