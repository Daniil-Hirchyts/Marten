import Foundation

/// Configuration for CloudKit synchronization.
public struct CloudKitConfiguration: Equatable, Sendable {

    /// Timing parameters for sync operations.
    public struct SyncTiming: Equatable, Sendable {
        /// Minimum interval between batched push operations.
        public var batchInterval: TimeInterval

        /// Interval for periodic fetch operations.
        public var fetchInterval: TimeInterval

        /// Initial retry backoff duration.
        public var retryBackoff: TimeInterval

        /// Maximum number of retry attempts.
        public var maxRetries: Int

        public static let `default` = SyncTiming(
            batchInterval: 2.0,
            fetchInterval: 300.0,
            retryBackoff: 1.0,
            maxRetries: 3
        )

        public init(
            batchInterval: TimeInterval = 2.0,
            fetchInterval: TimeInterval = 300.0,
            retryBackoff: TimeInterval = 1.0,
            maxRetries: Int = 3
        ) {
            self.batchInterval = batchInterval
            self.fetchInterval = fetchInterval
            self.retryBackoff = retryBackoff
            self.maxRetries = maxRetries
        }
    }

    /// The current CloudKit environment.
    public var environment: CloudKitEnvironment

    private var containerIdentifiers: [CloudKitEnvironment: String]
    private var zoneNames: [CloudKitEnvironment: String]

    /// The CloudKit container identifier for the current environment.
    public var containerIdentifier: String {
        get { containerIdentifiers[environment] ?? "" }
        set { containerIdentifiers[environment] = newValue }
    }

    /// The name of the custom zone in the private database for the current environment.
    public var zoneName: String {
        get { zoneNames[environment] ?? "" }
        set { zoneNames[environment] = newValue }
    }

    /// Timing configuration for sync operations.
    public var syncTiming: SyncTiming

    public static let `default` = CloudKitConfiguration(
        containerIdentifier: "iCloud.com.hirchyts.marten",
        zoneName: "MartenZone",
        syncTiming: .default
    )

    public init(
        containerIdentifier: String,
        zoneName: String = "MartenZone",
        syncTiming: SyncTiming = .default,
        environment: CloudKitEnvironment = .production
    ) {
        self.environment = environment
        self.syncTiming = syncTiming
        
        var identifiers: [CloudKitEnvironment: String] = [:]
        var zones: [CloudKitEnvironment: String] = [:]
        
        for env in CloudKitEnvironment.allCases {
            identifiers[env] = containerIdentifier
            zones[env] = zoneName
        }
        
        self.containerIdentifiers = identifiers
        self.zoneNames = zones
    }
    
    /// Sets the container identifier for a specific environment.
    public mutating func setContainerIdentifier(_ identifier: String, for environment: CloudKitEnvironment) {
        containerIdentifiers[environment] = identifier
    }
    
    /// Sets the zone name for a specific environment.
    public mutating func setZoneName(_ name: String, for environment: CloudKitEnvironment) {
        zoneNames[environment] = name
    }
}
