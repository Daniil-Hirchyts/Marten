import CloudKit
import Combine
import CoreData
import Foundation

/// Handles outbound sync for shared pinboard data.
///
/// Listens to Core Data saves and routes shared entities to either:
/// - private database (owner-shared zones)
/// - shared database (participant-shared zones)
public final class SharedOutboundSyncEngine: @unchecked Sendable {
    private struct PendingZoneBatch {
        var savesByID: [CKRecord.ID: CKRecord] = [:]
        var deletes: Set<CKRecord.ID> = []
        var attempts: Int = 0
    }

    private let retryBackoff: TimeInterval = 2.0
    private let maxRetries: Int = 3

    private struct SharedPinboardRoutingSnapshot {
        var routingByPinboardID: [UUID: SyncRoutingInfo] = [:]
        var pinboardIDsByZone: [CKRecordZone.ID: Set<UUID>] = [:]
        var routingByZone: [CKRecordZone.ID: SyncRoutingInfo] = [:]
    }

    private struct PendingAssetAttachmentRetry {
        var attempts: Int
    }

    private let persistenceController: PersistenceController
    private let privateDatabase: OutboundCloudDatabase
    private let sharedDatabase: OutboundCloudDatabase
    private let shareZoneRegistry: ShareZoneRegistry
    private let recordMapper: CloudRecordMapper
    private let isSyncEnabled: @Sendable () -> Bool
    private let assetSyncManager: AssetSyncManager
    private let attachmentRetryBackoff: TimeInterval
    private let attachmentMaxRetries: Int

    private let stateQueue = DispatchQueue(label: "com.hirchyts.marten.sync.shared.outbound", qos: .utility)
    private var saveObserver: NSObjectProtocol?
    private var flushTimer: DispatchWorkItem?
    private var pendingPrivateByZone: [CKRecordZone.ID: PendingZoneBatch] = [:]
    private var pendingSharedByZone: [CKRecordZone.ID: PendingZoneBatch] = [:]
    private var pendingAssetAttachmentRetries: [NSManagedObjectID: PendingAssetAttachmentRetry] = [:]
    private var inFlight = false
    private var flushCompletionContinuations: [CheckedContinuation<Void, Never>] = []
    private let debounceInterval: TimeInterval
    private let preparationErrorSubject = PassthroughSubject<SyncRecordPreparationError, Never>()

    public var preparationErrorPublisher: AnyPublisher<SyncRecordPreparationError, Never> {
        preparationErrorSubject.eraseToAnyPublisher()
    }

    public init(
        persistenceController: PersistenceController,
        privateDatabase: OutboundCloudDatabase,
        sharedDatabase: OutboundCloudDatabase,
        shareZoneRegistry: ShareZoneRegistry,
        recordMapper: CloudRecordMapper,
        debounceInterval: TimeInterval = 2.0,
        isSyncEnabled: @escaping @Sendable () -> Bool = { true },
        assetSyncManager: AssetSyncManager = AssetSyncManager(),
        attachmentRetryBackoff: TimeInterval = CloudKitConfiguration.SyncTiming.default.retryBackoff,
        attachmentMaxRetries: Int = CloudKitConfiguration.SyncTiming.default.maxRetries
    ) {
        self.persistenceController = persistenceController
        self.privateDatabase = privateDatabase
        self.sharedDatabase = sharedDatabase
        self.shareZoneRegistry = shareZoneRegistry
        self.recordMapper = recordMapper
        self.debounceInterval = debounceInterval
        self.isSyncEnabled = isSyncEnabled
        self.assetSyncManager = assetSyncManager
        self.attachmentRetryBackoff = attachmentRetryBackoff
        self.attachmentMaxRetries = attachmentMaxRetries
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
            resumeFlushCompletionContinuations()
        }
    }

    public func flushNow() {
        scheduleFlush(after: 0)
    }

    public func flushAndAwait() async {
        let hasPending = stateQueue.sync {
            self.hasPendingWork
        }
        guard hasPending else { return }

        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if !self.hasPendingWork {
                    continuation.resume()
                    return
                }
                self.flushCompletionContinuations.append(continuation)
                self.scheduleFlush(after: 0)
            }
        }
    }

    private var hasPendingWork: Bool {
        inFlight || pendingPrivateByZone.isEmpty == false || pendingSharedByZone.isEmpty == false
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        guard let coordinator = context.persistentStoreCoordinator,
              coordinator == persistenceController.container.persistentStoreCoordinator else { return }

        if SyncTransactionAuthor.isInboundSync(context.transactionAuthor) {
            return
        }

        guard let userInfo = notification.userInfo else { return }
        let insertedObjects = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updatedObjects = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deletedObjects = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []
        if insertedObjects.isEmpty, updatedObjects.isEmpty, deletedObjects.isEmpty { return }

        let saveObjectIDs = insertedObjects.union(updatedObjects).map(\.objectID)
        let deleted = Array(deletedObjects)
        let bgContext = persistenceController.newBackgroundContext()

        stateQueue.async { [weak self] in
            guard let self else { return }

            bgContext.performAndWait {
                let routingSnapshot = self.buildRoutingSnapshot(in: bgContext)

                for objectID in saveObjectIDs {
                    guard let object = try? bgContext.existingObject(with: objectID) else { continue }
                    self.routeSave(object, routingSnapshot: routingSnapshot)
                }

                for object in deleted {
                    self.routeDeletion(object, routingSnapshot: routingSnapshot)
                }
            }

            if self.isSyncEnabled() {
                self.scheduleFlush(after: self.debounceInterval)
            }
        }
    }

    private func buildRoutingSnapshot(in context: NSManagedObjectContext) -> SharedPinboardRoutingSnapshot {
        var snapshot = SharedPinboardRoutingSnapshot()
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemMarten == NO AND shareMetadata != nil")

        let pinboards = (try? context.fetch(request)) ?? []
        for pinboard in pinboards {
            let routing = shareZoneRegistry.routingInfo(for: pinboard)
            snapshot.routingByPinboardID[pinboard.id] = routing
            snapshot.pinboardIDsByZone[routing.zoneID, default: []].insert(pinboard.id)
            snapshot.routingByZone[routing.zoneID] = routing
        }
        return snapshot
    }

    private func routeSave(_ object: NSManagedObject, routingSnapshot: SharedPinboardRoutingSnapshot) {
        if let pinboard = object as? Pinboard {
            guard pinboard.isShared else { return }
            let routing = shareZoneRegistry.routingInfo(for: pinboard)
            guard isSharedRouting(routing) else { return }
            let record = recordMapper.mapToRecord(pinboard, zoneID: routing.zoneID)
            enqueueSave(record: record, routing: routing)
            return
        }

        if let item = object as? ClipItem {
            routeSharedItemSave(item, routingSnapshot: routingSnapshot)
            return
        }

        if let representation = object as? ClipRepresentation {
            routeSharedRepresentationSave(representation)
            return
        }

        if let preview = object as? LinkPreview {
            guard let parent = preview.clipItem else { return }
            let routing = shareZoneRegistry.routingInfo(for: parent)
            guard isSharedRouting(routing) else { return }
            let record = recordMapper.mapToRecord(preview, parentItemID: parent.id, zoneID: routing.zoneID)
            enqueueSave(record: record, routing: routing)
        }
    }

    private func routeSharedRepresentationSave(
        _ representation: ClipRepresentation,
        previousAttachmentRetryAttempts: Int = 0
    ) {
        guard let parent = representation.clipItem else { return }
        let routing = shareZoneRegistry.routingInfo(for: parent)
        guard isSharedRouting(routing) else { return }

        let record = recordMapper.mapToRecord(
            representation,
            parentItemID: parent.id,
            zoneID: routing.zoneID
        )

        do {
            try assetSyncManager.attachAssetIfNeededSync(from: representation, to: record)
        } catch {
            handleRepresentationAttachmentFailure(
                objectID: representation.objectID,
                representationID: representation.id,
                previousAttempts: previousAttachmentRetryAttempts,
                error: error
            )
            return
        }

        enqueueSave(record: record, routing: routing)
    }

    private func routeSharedItemSave(
        _ item: ClipItem,
        routingSnapshot: SharedPinboardRoutingSnapshot
    ) {
        let routing = shareZoneRegistry.routingInfo(for: item)
        guard isSharedRouting(routing) else { return }

        let itemRecord = recordMapper.mapToRecord(item, zoneID: routing.zoneID)
        enqueueSave(record: itemRecord, routing: routing)

        var activeByZone: [CKRecordZone.ID: Set<UUID>] = [:]
        let sharedPinboards = (item.pinboards ?? []).filter { !$0.isSystemMarten && $0.isShared }
        for pinboard in sharedPinboards {
            let pinboardRouting = shareZoneRegistry.routingInfo(for: pinboard)
            guard isSharedRouting(pinboardRouting) else { continue }
            activeByZone[pinboardRouting.zoneID, default: []].insert(pinboard.id)
            let membershipID = CKRecord.ID.deterministicMembershipUUID(
                clipItemID: item.id,
                pinboardID: pinboard.id
            )
            let membership = CloudRecordMapper.PinboardMembershipData(
                id: membershipID,
                clipItemID: item.id,
                pinboardID: pinboard.id
            )
            let membershipRecord = recordMapper.mapToRecord(membership, zoneID: pinboardRouting.zoneID)
            enqueueSave(record: membershipRecord, routing: pinboardRouting)
        }

        for (zoneID, allPinboardsInZone) in routingSnapshot.pinboardIDsByZone {
            guard let zoneRouting = routingSnapshot.routingByZone[zoneID] else { continue }
            let activePinboards = activeByZone[zoneID] ?? []
            for stalePinboardID in allPinboardsInZone.subtracting(activePinboards) {
                enqueueDelete(
                    recordID: .membershipID(
                        clipItemID: item.id,
                        pinboardID: stalePinboardID,
                        zoneID: zoneID
                    ),
                    routing: zoneRouting
                )
            }
        }
    }

    private func routeDeletion(
        _ object: NSManagedObject,
        routingSnapshot: SharedPinboardRoutingSnapshot
    ) {
        if let item = object as? ClipItem {
            let sharedPinboards = (item.pinboards ?? []).filter { !$0.isSystemMarten && $0.isShared }
            let routingByZone = Dictionary(
                uniqueKeysWithValues: sharedPinboards.map { pinboard in
                    let routing = shareZoneRegistry.routingInfo(for: pinboard)
                    return (routing.zoneID, routing)
                }
            )

            for (zoneID, routing) in routingByZone where isSharedRouting(routing) {
                enqueueDelete(recordID: .clipItemID(item.id, zoneID: zoneID), routing: routing)
                if let representations = item.representations {
                    for representation in representations {
                        enqueueDelete(
                            recordID: .clipRepresentationID(representation.id, zoneID: zoneID),
                            routing: routing
                        )
                    }
                }
                if let preview = item.linkPreview {
                    enqueueDelete(
                        recordID: .linkPreviewID(preview.id, zoneID: zoneID),
                        routing: routing
                    )
                }
            }

            for pinboard in sharedPinboards {
                let routing = shareZoneRegistry.routingInfo(for: pinboard)
                guard isSharedRouting(routing) else { continue }
                enqueueDelete(
                    recordID: .membershipID(
                        clipItemID: item.id,
                        pinboardID: pinboard.id,
                        zoneID: routing.zoneID
                    ),
                    routing: routing
                )
            }
            return
        }

        if let representation = object as? ClipRepresentation {
            guard let parent = representation.clipItem else { return }
            let routing = shareZoneRegistry.routingInfo(for: parent)
            guard isSharedRouting(routing) else { return }
            enqueueDelete(
                recordID: .clipRepresentationID(representation.id, zoneID: routing.zoneID),
                routing: routing
            )
            return
        }

        if let preview = object as? LinkPreview {
            guard let parent = preview.clipItem else { return }
            let routing = shareZoneRegistry.routingInfo(for: parent)
            guard isSharedRouting(routing) else { return }
            enqueueDelete(
                recordID: .linkPreviewID(preview.id, zoneID: routing.zoneID),
                routing: routing
            )
            return
        }

        if let pinboard = object as? Pinboard {
            guard pinboard.isShared else { return }
            let routing = shareZoneRegistry.routingInfo(for: pinboard)
            guard isSharedRouting(routing) else { return }
            enqueueDelete(recordID: .pinboardID(pinboard.id, zoneID: routing.zoneID), routing: routing)

            guard let items = pinboard.items else { return }
            for item in items {
                enqueueDelete(
                    recordID: .membershipID(
                        clipItemID: item.id,
                        pinboardID: pinboard.id,
                        zoneID: routing.zoneID
                    ),
                    routing: routing
                )
            }
            return
        }

        // If a stale zone snapshot still has this pinboard membership, clean it up proactively.
        if let item = object as? ClipItem, routingSnapshot.pinboardIDsByZone.isEmpty == false {
            for (zoneID, pinboardIDs) in routingSnapshot.pinboardIDsByZone {
                guard let routing = routingSnapshot.routingByZone[zoneID] else { continue }
                for pinboardID in pinboardIDs {
                    enqueueDelete(
                        recordID: .membershipID(
                            clipItemID: item.id,
                            pinboardID: pinboardID,
                            zoneID: zoneID
                        ),
                        routing: routing
                    )
                }
            }
        }
    }

    private func isSharedRouting(_ routing: SyncRoutingInfo) -> Bool {
        routing.database == .sharedDB || routing.zoneID.zoneName.hasPrefix("SharedPinboard-")
    }

    private func enqueueSave(record: CKRecord, routing: SyncRoutingInfo) {
        switch routing.database {
        case .privateDB:
            var batch = pendingPrivateByZone[routing.zoneID] ?? PendingZoneBatch()
            batch.deletes.remove(record.recordID)
            batch.savesByID[record.recordID] = record
            pendingPrivateByZone[routing.zoneID] = batch
        case .sharedDB:
            var batch = pendingSharedByZone[routing.zoneID] ?? PendingZoneBatch()
            batch.deletes.remove(record.recordID)
            batch.savesByID[record.recordID] = record
            pendingSharedByZone[routing.zoneID] = batch
        }
    }

    private func enqueueDelete(recordID: CKRecord.ID, routing: SyncRoutingInfo) {
        switch routing.database {
        case .privateDB:
            var batch = pendingPrivateByZone[routing.zoneID] ?? PendingZoneBatch()
            batch.savesByID.removeValue(forKey: recordID)
            batch.deletes.insert(recordID)
            pendingPrivateByZone[routing.zoneID] = batch
        case .sharedDB:
            var batch = pendingSharedByZone[routing.zoneID] ?? PendingZoneBatch()
            batch.savesByID.removeValue(forKey: recordID)
            batch.deletes.insert(recordID)
            pendingSharedByZone[routing.zoneID] = batch
        }
    }

    private func handleRepresentationAttachmentFailure(
        objectID: NSManagedObjectID,
        representationID: UUID,
        previousAttempts: Int,
        error: Error
    ) {
        let baseAttempts = max(
            previousAttempts,
            pendingAssetAttachmentRetries[objectID]?.attempts ?? 0
        )
        let nextAttempts = baseAttempts + 1
        let reason = localizedReason(for: error)

        preparationErrorSubject.send(
            .assetAttachmentFailed(
                engine: "SharedOutboundSyncEngine",
                representationID: representationID,
                reason: reason
            )
        )

        if nextAttempts >= attachmentMaxRetries {
            pendingAssetAttachmentRetries.removeValue(forKey: objectID)
            return
        }

        pendingAssetAttachmentRetries[objectID] = PendingAssetAttachmentRetry(
            attempts: nextAttempts
        )

        guard isSyncEnabled() else { return }
        guard pendingPrivateByZone.isEmpty, pendingSharedByZone.isEmpty, !inFlight else { return }
        scheduleFlush(after: attachmentRetryDelay(forAttempt: nextAttempts))
    }

    private func processPendingAttachmentRetries() {
        guard !pendingAssetAttachmentRetries.isEmpty else { return }

        let retries = pendingAssetAttachmentRetries
        pendingAssetAttachmentRetries.removeAll()
        let backgroundContext = persistenceController.newBackgroundContext()

        backgroundContext.performAndWait {
            for (objectID, retryState) in retries {
                guard
                    let object = try? backgroundContext.existingObject(with: objectID),
                    let representation = object as? ClipRepresentation
                else {
                    continue
                }
                routeSharedRepresentationSave(
                    representation,
                    previousAttachmentRetryAttempts: retryState.attempts
                )
            }
        }
    }

    private func attachmentRetryDelay(forAttempt attempt: Int) -> TimeInterval {
        attachmentRetryBackoff * pow(2.0, Double(max(0, attempt - 1)))
    }

    private func localizedReason(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? String(describing: error) : message
    }

    private func scheduleFlush(after delay: TimeInterval) {
        flushTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.beginFlush()
        }
        flushTimer = work
        stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginFlush() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSyncEnabled() else { return }
            guard self.inFlight == false else { return }

            self.processPendingAttachmentRetries()

            guard self.pendingPrivateByZone.isEmpty == false || self.pendingSharedByZone.isEmpty == false else {
                self.resumeFlushCompletionContinuations()
                return
            }

            let privateBatches = self.pendingPrivateByZone
            let sharedBatches = self.pendingSharedByZone
            self.pendingPrivateByZone.removeAll()
            self.pendingSharedByZone.removeAll()
            self.inFlight = true

            Task { [weak self] in
                await self?.process(
                    privateBatches: privateBatches,
                    sharedBatches: sharedBatches
                )
            }
        }
    }

    private func process(
        privateBatches: [CKRecordZone.ID: PendingZoneBatch],
        sharedBatches: [CKRecordZone.ID: PendingZoneBatch]
    ) async {
        var retryPrivate: [CKRecordZone.ID: PendingZoneBatch] = [:]
        var retryShared: [CKRecordZone.ID: PendingZoneBatch] = [:]

        for (zoneID, batch) in privateBatches {
            let records = CloudRecordUploadOrdering.sortedForUpload(batch.savesByID.values)
            let deletions = Array(batch.deletes)
            let result = await privateDatabase.modifyRecords(saving: records, deleting: deletions)
            collectRetryWork(
                for: batch,
                result: result,
                into: &retryPrivate[zoneID, default: PendingZoneBatch()]
            )
        }

        for (zoneID, batch) in sharedBatches {
            let records = CloudRecordUploadOrdering.sortedForUpload(batch.savesByID.values)
            let deletions = Array(batch.deletes)
            let result = await sharedDatabase.modifyRecords(saving: records, deleting: deletions)
            collectRetryWork(
                for: batch,
                result: result,
                into: &retryShared[zoneID, default: PendingZoneBatch()]
            )
        }

        stateQueue.async { [weak self] in
            guard let self else { return }
            self.inFlight = false

            let maxRetryAttempts: Int = {
                let privateAttempts = retryPrivate.values.map(\.attempts).max() ?? 0
                let sharedAttempts = retryShared.values.map(\.attempts).max() ?? 0
                return max(privateAttempts, sharedAttempts)
            }()

            if retryPrivate.isEmpty == false {
                self.mergePendingBatches(retryPrivate, into: &self.pendingPrivateByZone)
            }
            if retryShared.isEmpty == false {
                self.mergePendingBatches(retryShared, into: &self.pendingSharedByZone)
            }

            self.resumeFlushCompletionContinuations()
            if self.pendingPrivateByZone.isEmpty == false || self.pendingSharedByZone.isEmpty == false {
                let delay = maxRetryAttempts > 0 ? self.retryDelay(forAttempts: maxRetryAttempts) : 0
                self.scheduleFlush(after: delay)
            }
        }
    }

    private func collectRetryWork(
        for batch: PendingZoneBatch,
        result: OutboundCloudDatabaseModifyResult,
        into retry: inout PendingZoneBatch
    ) {
        let nextAttempts = batch.attempts + 1
        retry.attempts = nextAttempts
        guard nextAttempts <= maxRetries else { return }

        var failedSaveIDs = Set(result.saveErrors.keys)
        if result.operationError != nil, result.saveErrors.isEmpty {
            failedSaveIDs.formUnion(batch.savesByID.keys)
        }
        for recordID in failedSaveIDs {
            // For .serverRecordChanged errors, drop the stale local record and let inbound sync resolve it.
            if let error = result.saveErrors[recordID] as? CKError,
               error.code == .serverRecordChanged {
                continue
            }
            guard let record = batch.savesByID[recordID] else { continue }
            retry.savesByID[recordID] = record
        }

        var failedDeleteIDs = Set(result.deleteErrors.keys)
        if result.operationError != nil, result.deleteErrors.isEmpty {
            failedDeleteIDs.formUnion(batch.deletes)
        }
        retry.deletes.formUnion(failedDeleteIDs)
    }

    private func retryDelay(forAttempts attempts: Int) -> TimeInterval {
        retryBackoff * pow(2.0, Double(max(0, attempts - 1)))
    }

    private func mergePendingBatches(
        _ source: [CKRecordZone.ID: PendingZoneBatch],
        into destination: inout [CKRecordZone.ID: PendingZoneBatch]
    ) {
        for (zoneID, incoming) in source {
            var target = destination[zoneID] ?? PendingZoneBatch()
            target.savesByID.merge(incoming.savesByID) { _, new in new }
            target.deletes.formUnion(incoming.deletes)
            for recordID in incoming.savesByID.keys {
                target.deletes.remove(recordID)
            }
            destination[zoneID] = target
        }
    }

    private func resumeFlushCompletionContinuations() {
        guard flushCompletionContinuations.isEmpty == false else { return }
        let continuations = flushCompletionContinuations
        flushCompletionContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
    }
}
