import CloudKit
import CoreData
import Foundation

/// Handles outbound sync for shared pinboard data.
///
/// Listens to Core Data context saves, filters by transaction author to avoid loops,
/// and uses ShareZoneRegistry to route each entity to the correct database and zone.
public final class SharedOutboundSyncEngine: @unchecked Sendable {
    private let persistenceController: PersistenceController
    private let privateDatabase: OutboundCloudDatabase
    private let sharedDatabase: OutboundCloudDatabase
    private let shareZoneRegistry: ShareZoneRegistry
    private let recordMapper: CloudRecordMapper
    private let isSyncEnabled: @Sendable () -> Bool

    private let stateQueue = DispatchQueue(label: "com.hirchyts.marten.sync.shared.outbound", qos: .utility)
    private var saveObserver: NSObjectProtocol?
    private var pendingPrivateSaves: [CKRecordZone.ID: [CKRecord]] = [:]
    private var pendingSharedSaves: [CKRecordZone.ID: [CKRecord]] = [:]
    private var flushTimer: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    public init(
        persistenceController: PersistenceController,
        privateDatabase: OutboundCloudDatabase,
        sharedDatabase: OutboundCloudDatabase,
        shareZoneRegistry: ShareZoneRegistry,
        recordMapper: CloudRecordMapper,
        debounceInterval: TimeInterval = 2.0,
        isSyncEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.persistenceController = persistenceController
        self.privateDatabase = privateDatabase
        self.sharedDatabase = sharedDatabase
        self.shareZoneRegistry = shareZoneRegistry
        self.recordMapper = recordMapper
        self.debounceInterval = debounceInterval
        self.isSyncEnabled = isSyncEnabled
    }

    deinit {
        stop()
    }

    public func start() {
        stateQueue.sync {
            guard saveObserver == nil else { return }
            saveObserver = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleContextDidSave(notification)
            }
        }
    }

    public func stop() {
        stateQueue.sync {
            if let saveObserver {
                NotificationCenter.default.removeObserver(saveObserver)
                self.saveObserver = nil
            }
            flushTimer?.cancel()
            flushTimer = nil
        }
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        guard let coordinator = context.persistentStoreCoordinator,
              coordinator == persistenceController.container.persistentStoreCoordinator else { return }

        // Skip saves from any inbound sync
        if let author = context.transactionAuthor,
           author == "private-inbound-sync" || author == "shared-inbound-sync" {
            return
        }

        guard let userInfo = notification.userInfo else { return }

        let insertedObjects = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updatedObjects = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        if insertedObjects.isEmpty, updatedObjects.isEmpty { return }

        let bgContext = persistenceController.newBackgroundContext()

        stateQueue.async { [weak self] in
            guard let self else { return }
            bgContext.performAndWait {
                let allObjects = insertedObjects.union(updatedObjects)
                for object in allObjects {
                    guard let bgObject = try? bgContext.existingObject(with: object.objectID) else { continue }
                    self.routeObject(bgObject)
                }
            }

            if self.isSyncEnabled() {
                self.scheduleFlush()
            }
        }
    }

    private func routeObject(_ object: NSManagedObject) {
        if let pinboard = object as? Pinboard, pinboard.isShared {
            let routing = shareZoneRegistry.routingInfo(for: pinboard)
            let record = recordMapper.mapToRecord(pinboard, zoneID: routing.zoneID)
            enqueue(record: record, routing: routing)
        } else if let item = object as? ClipItem {
            let routing = shareZoneRegistry.routingInfo(for: item)
            guard routing.database != .privateDB || routing.zoneID != shareZoneRegistry.routingInfo(for: item).zoneID else {
                // Only handle shared items; private items are handled by OutboundSyncEngine
                return
            }
            if routing.database == .sharedDB || routing.zoneID.zoneName.hasPrefix("SharedPinboard-") {
                let record = recordMapper.mapToRecord(item, zoneID: routing.zoneID)
                enqueue(record: record, routing: routing)
            }
        }
    }

    private func enqueue(record: CKRecord, routing: SyncRoutingInfo) {
        switch routing.database {
        case .privateDB:
            pendingPrivateSaves[routing.zoneID, default: []].append(record)
        case .sharedDB:
            pendingSharedSaves[routing.zoneID, default: []].append(record)
        }
    }

    private func scheduleFlush() {
        flushTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        flushTimer = work
        stateQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func flush() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSyncEnabled() else { return }

            let privateBatches = self.pendingPrivateSaves
            let sharedBatches = self.pendingSharedSaves
            self.pendingPrivateSaves.removeAll()
            self.pendingSharedSaves.removeAll()

            Task {
                for (_, records) in privateBatches {
                    _ = await self.privateDatabase.modifyRecords(saving: records, deleting: [])
                }
                for (_, records) in sharedBatches {
                    _ = await self.sharedDatabase.modifyRecords(saving: records, deleting: [])
                }
            }
        }
    }
}
