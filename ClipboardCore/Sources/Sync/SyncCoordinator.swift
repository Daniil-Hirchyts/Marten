import CloudKit
import Combine
import Foundation
import os.log

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
            return lhsError.localizedDescription == rhsError.localizedDescription
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

    /// Whether to log sync operations for debugging.
    public var debugLogging: Bool

    /// UserDefaults key for sync enabled preference.
    public var syncEnabledKey: String

    public static let `default` = SyncCoordinatorConfiguration(
        periodicFetchInterval: 30.0,
        debugLogging: false,
        syncEnabledKey: "com.paste.syncEnabled"
    )

    public init(
        periodicFetchInterval: TimeInterval = 30.0,
        debugLogging: Bool = false,
        syncEnabledKey: String = "com.paste.syncEnabled"
    ) {
        self.periodicFetchInterval = periodicFetchInterval
        self.debugLogging = debugLogging
        self.syncEnabledKey = syncEnabledKey
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
    @Published public private(set) var lastSyncDate: Date?

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

    // MARK: - Dependencies

    private let cloudKitManager: CloudKitManager
    private let outboundEngine: OutboundSyncEngine
    private let inboundEngine: InboundSyncEngine
    private let assetSyncManager: AssetSyncManager
    private let persistenceController: PersistenceController
    private let configuration: SyncCoordinatorConfiguration
    private let userDefaults: UserDefaults

    // MARK: - Private State

    private var periodicSyncTask: Task<Void, Never>?
    private var isSyncInProgress = false
    private let syncLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private let errorSubject = PassthroughSubject<CloudKitSyncError, Never>()
    private var isSetUp = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.paste",
        category: "SyncCoordinator"
    )

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
        userDefaults: UserDefaults = .standard
    ) {
        self.cloudKitManager = cloudKitManager
        self.outboundEngine = outboundEngine
        self.inboundEngine = inboundEngine
        self.assetSyncManager = assetSyncManager
        self.persistenceController = persistenceController
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.syncEnabled = userDefaults.bool(forKey: configuration.syncEnabledKey)

        setupObservers()
    }

    deinit {
        periodicSyncTask?.cancel()
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
            // Verify account and set up CloudKit
            try await cloudKitManager.performCompleteSetup()
            log("CloudKit setup complete")

            // Start outbound engine (monitors Core Data saves)
            outboundEngine.start()
            log("Outbound engine started")

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
        periodicSyncTask?.cancel()
        periodicSyncTask = nil

        // Stop outbound engine
        outboundEngine.stop()

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
            // Flush outbound changes first
            outboundEngine.flushNow()

            // Wait a brief moment for outbound to process
            try await Task.sleep(nanoseconds: 100_000_000)

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

            updateProgress(SyncProgress(
                itemsQueued: 0,
                itemsUploaded: 0,
                itemsDownloaded: result.fetchedRecordCount
            ))

            lastSyncDate = Date()
            updateStatus(.synced)

            log("Push-triggered sync completed: \(result.fetchedRecordCount) fetched")
        } catch {
            log("Push-triggered sync failed: \(error.localizedDescription)")
            if let syncError = error as? CloudKitSyncError {
                handleError(syncError)
            }
        }
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
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
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
        periodicSyncTask?.cancel()

        periodicSyncTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.configuration.periodicFetchInterval * 1_000_000_000))

                    guard !Task.isCancelled else { break }
                    guard self.syncEnabled, self.isSetUp else { continue }

                    await self.performPeriodicInboundSync()
                } catch {
                    break
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
        } catch {
            log("Periodic sync failed: \(error.localizedDescription)")
            if let syncError = error as? CloudKitSyncError {
                handleError(syncError)
            }
        }
    }

    private func updateStatus(_ newStatus: SyncStatus) {
        status = newStatus
    }

    private func updateProgress(_ newProgress: SyncProgress) {
        progress = newProgress
    }

    private func handleError(_ error: CloudKitSyncError) {
        log("Sync error: \(error.localizedDescription)")
        updateStatus(.error(error))
        errorSubject.send(error)
    }

    private func acquireSyncLock() -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }

        if isSyncInProgress {
            return false
        }
        isSyncInProgress = true
        return true
    }

    private func releaseSyncLock() {
        syncLock.lock()
        isSyncInProgress = false
        syncLock.unlock()
    }

    private func log(_ message: String) {
        if configuration.debugLogging {
            Self.logger.debug("\(message)")
        }
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

        return SyncCoordinator(
            cloudKitManager: cloudKitManager,
            outboundEngine: outboundEngine,
            inboundEngine: inboundEngine,
            assetSyncManager: assetSyncManager,
            persistenceController: persistenceController,
            configuration: SyncCoordinatorConfiguration(
                periodicFetchInterval: 30.0,
                debugLogging: cloudKitConfiguration.debugLogging
            ),
            userDefaults: userDefaults
        )
    }
}
