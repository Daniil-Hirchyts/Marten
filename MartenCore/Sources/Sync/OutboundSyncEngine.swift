import CloudKit
import Combine
import CoreData
import Foundation

public protocol OutboundCloudDatabase: AnyObject, Sendable {
    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID]
    ) async -> OutboundCloudDatabaseModifyResult
}

public struct OutboundCloudDatabaseModifyResult: Sendable {
    public var savedRecords: [CKRecord]
    public var deletedRecordIDs: [CKRecord.ID]
    public var saveErrors: [CKRecord.ID: Error]
    public var deleteErrors: [CKRecord.ID: Error]
    public var operationError: Error?

    public init(
        savedRecords: [CKRecord] = [],
        deletedRecordIDs: [CKRecord.ID] = [],
        saveErrors: [CKRecord.ID: Error] = [:],
        deleteErrors: [CKRecord.ID: Error] = [:],
        operationError: Error? = nil
    ) {
        self.savedRecords = savedRecords
        self.deletedRecordIDs = deletedRecordIDs
        self.saveErrors = saveErrors
        self.deleteErrors = deleteErrors
        self.operationError = operationError
    }
}

extension CKDatabase: OutboundCloudDatabase {
    public func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID]
    ) async -> OutboundCloudDatabaseModifyResult {
        await withCheckedContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave.isEmpty ? nil : recordsToSave,
                recordIDsToDelete: recordIDsToDelete.isEmpty ? nil : recordIDsToDelete
            )
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            var savedRecords: [CKRecord] = []
            var deletedIDs: [CKRecord.ID] = []
            var saveErrors: [CKRecord.ID: Error] = [:]
            var deleteErrors: [CKRecord.ID: Error] = [:]

            operation.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let record):
                    savedRecords.append(record)
                case .failure(let error):
                    saveErrors[recordID] = error
                }
            }

            operation.perRecordDeleteBlock = { recordID, result in
                switch result {
                case .success:
                    deletedIDs.append(recordID)
                case .failure(let error):
                    deleteErrors[recordID] = error
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(
                        returning: OutboundCloudDatabaseModifyResult(
                            savedRecords: savedRecords,
                            deletedRecordIDs: deletedIDs,
                            saveErrors: saveErrors,
                            deleteErrors: deleteErrors,
                            operationError: nil
                        )
                    )
                case .failure(let error):
                    continuation.resume(
                        returning: OutboundCloudDatabaseModifyResult(
                            savedRecords: savedRecords,
                            deletedRecordIDs: deletedIDs,
                            saveErrors: saveErrors,
                            deleteErrors: deleteErrors,
                            operationError: error
                        )
                    )
                }
            }

            self.add(operation)
        }
    }
}

public protocol OutboundConflictResolving: Sendable {
    func resolve(localRecord: CKRecord, serverRecord: CKRecord) async throws -> CKRecord
}

public struct DefaultOutboundConflictResolver: OutboundConflictResolving {
    public init() {}

    public func resolve(localRecord: CKRecord, serverRecord: CKRecord) async throws -> CKRecord {
        // For ClipItem and Pinboard records, use last-writer-wins based on modifiedAt.
        // This prevents a stale local record from overwriting a newer server edit on shared pinboards.
        let modifiedAtKey: String?
        switch localRecord.cloudRecordType {
        case .clipItem: modifiedAtKey = ClipItemField.modifiedAt.rawValue
        case .pinboard: modifiedAtKey = PinboardField.modifiedAt.rawValue
        default: modifiedAtKey = nil
        }

        if let key = modifiedAtKey,
           let localDate = localRecord[key] as? Date,
           let serverDate = serverRecord[key] as? Date,
           localDate < serverDate {
            // Server is newer — return server record unmodified so the conflict clears.
            return serverRecord
        }

        // Local is newer (or no timestamp to compare) — apply local keys over server base record.
        for key in localRecord.allKeys() {
            serverRecord[key] = localRecord[key]
        }
        return serverRecord
    }
}

/// `stateQueue` serializes all accesses to mutable state in this type.
public final class OutboundSyncEngine: @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var debounceInterval: TimeInterval
        public var maxRecordsPerBatch: Int
        public var retryBackoff: TimeInterval
        public var maxRetries: Int

        public init(
            debounceInterval: TimeInterval = CloudKitConfiguration.SyncTiming.default.batchInterval,
            maxRecordsPerBatch: Int = 400,
            retryBackoff: TimeInterval = CloudKitConfiguration.SyncTiming.default.retryBackoff,
            maxRetries: Int = CloudKitConfiguration.SyncTiming.default.maxRetries
        ) {
            self.debounceInterval = debounceInterval
            self.maxRecordsPerBatch = maxRecordsPerBatch
            self.retryBackoff = retryBackoff
            self.maxRetries = maxRetries
        }
    }

    public enum RecordStatus: Equatable {
        case pending
        case uploading
        case uploaded
        case failed
    }

    private struct WorkItem {
        var saveRecordsByID: [CKRecord.ID: CKRecord]
        var deleteIDs: Set<CKRecord.ID>
        var attempts: Int
    }

    private struct PendingAssetAttachmentRetry {
        var recordID: CKRecord.ID
        var attempts: Int
    }

    private let persistenceController: PersistenceController
    private let database: OutboundCloudDatabase
    private let zoneID: CKRecordZone.ID
    private let mapper: CloudRecordMapper
    private let configuration: Configuration
    private let isSyncEnabled: @Sendable () -> Bool
    private let conflictResolver: OutboundConflictResolving
    private let shareZoneRegistry: ShareZoneRegistry?
    private let assetSyncManager: AssetSyncManager

    private let stateQueue = DispatchQueue(label: "com.hirchyts.marten.sync.outbound", qos: .utility)
    private var saveObserver: NSObjectProtocol?
    private var flushTimer: DispatchWorkItem?
    private var pendingSaves: [CKRecord.ID: CKRecord] = [:]
    private var pendingDeletes: Set<CKRecord.ID> = []
    private var pendingAssetAttachmentRetries: [NSManagedObjectID: PendingAssetAttachmentRetry] = [:]
    private var statusByID: [CKRecord.ID: RecordStatus] = [:]
    private var inFlight: WorkItem?
    private var flushCompletionContinuations: [CheckedContinuation<Void, Never>] = []
    private let preparationErrorSubject = PassthroughSubject<SyncRecordPreparationError, Never>()

    public var preparationErrorPublisher: AnyPublisher<SyncRecordPreparationError, Never> {
        preparationErrorSubject.eraseToAnyPublisher()
    }

    public init(
        persistenceController: PersistenceController,
        database: OutboundCloudDatabase,
        zoneID: CKRecordZone.ID,
        configuration: Configuration = Configuration(),
        isSyncEnabled: @escaping @Sendable () -> Bool = { true },
        conflictResolver: OutboundConflictResolving = DefaultOutboundConflictResolver(),
        shareZoneRegistry: ShareZoneRegistry? = nil,
        assetSyncManager: AssetSyncManager = AssetSyncManager()
    ) {
        self.persistenceController = persistenceController
        self.database = database
        self.zoneID = zoneID
        self.mapper = CloudRecordMapper(zoneID: zoneID)
        self.configuration = configuration
        self.isSyncEnabled = isSyncEnabled
        self.conflictResolver = conflictResolver
        self.shareZoneRegistry = shareZoneRegistry
        self.assetSyncManager = assetSyncManager
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
        // Flush any saves that accumulated while the engine was stopped
        scheduleFlush(after: 0)
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

    public func status(for recordID: CKRecord.ID) -> RecordStatus {
        stateQueue.sync { statusByID[recordID] ?? .pending }
    }

    public func flushNow() {
        scheduleFlush(after: 0)
    }

    public func flushAndAwait() async {
        let hasPending: Bool = stateQueue.sync {
            !self.pendingSaves.isEmpty || !self.pendingDeletes.isEmpty || self.inFlight != nil
        }
        guard hasPending else { return }

        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.pendingSaves.isEmpty && self.pendingDeletes.isEmpty && self.inFlight == nil {
                    continuation.resume()
                    return
                }
                self.flushCompletionContinuations.append(continuation)
                self.scheduleFlush(after: 0)
            }
        }
    }

    /// Queues all existing clip items for one-time membership backfill.
    ///
    /// This emits membership records using the same enqueue path as normal saves, including
    /// stale membership deletions for custom pinboards no longer assigned to each item.
    public func enqueueMembershipBackfillForAllItems() async {
        let context = persistenceController.newBackgroundContext()
        var objectIDs: [NSManagedObjectID] = []

        context.performAndWait {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "ClipItem")
            request.resultType = .managedObjectIDResultType
            objectIDs = (try? context.fetch(request)) ?? []
        }

        guard !objectIDs.isEmpty else { return }

        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.enqueueSaveObjectIDs(objectIDs)
                if self.isSyncEnabled() {
                    self.scheduleFlush(after: 0)
                }
                continuation.resume()
            }
        }
    }

    /// Queues all asset-backed representations for one-time re-upload backfill.
    ///
    /// Returns the number of representations enqueued.
    public func enqueueAssetRepresentationBackfill() async -> Int {
        let context = persistenceController.newBackgroundContext()
        var objectIDs: [NSManagedObjectID] = []

        context.performAndWait {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "ClipRepresentation")
            request.resultType = .managedObjectIDResultType
            request.predicate = NSPredicate(format: "assetRef != nil")
            objectIDs = (try? context.fetch(request)) ?? []
        }

        guard !objectIDs.isEmpty else { return 0 }

        return await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }
                self.enqueueSaveObjectIDs(objectIDs)
                if self.isSyncEnabled() {
                    self.scheduleFlush(after: 0)
                }
                continuation.resume(returning: objectIDs.count)
            }
        }
    }

    /// Fetches ClipItems with modifiedAt >= `date` and enqueues them for upload.
    /// Use when extensions have written items while the main app was suspended.
    public func enqueueItems(modifiedSince date: Date) async {
        let context = persistenceController.newBackgroundContext()
        var objectIDs: [NSManagedObjectID] = []

        context.performAndWait {
            // Fetch modified items and their associated representations/previews
            let itemRequest = NSFetchRequest<ClipItem>(entityName: "ClipItem")
            itemRequest.predicate = NSPredicate(format: "modifiedAt >= %@", date as NSDate)
            if let items = try? context.fetch(itemRequest) {
                for item in items {
                    objectIDs.append(item.objectID)
                    if let representations = item.representations {
                        objectIDs.append(contentsOf: representations.map(\.objectID))
                    }
                    if let preview = item.linkPreview {
                        objectIDs.append(preview.objectID)
                    }
                }
            }

            // Fetch newly created pinboards
            let pinboardRequest = NSFetchRequest<Pinboard>(entityName: "Pinboard")
            pinboardRequest.predicate = NSPredicate(format: "createdAt >= %@", date as NSDate)
            if let pinboards = try? context.fetch(pinboardRequest) {
                objectIDs.append(contentsOf: pinboards.map(\.objectID))
            }
        }

        guard !objectIDs.isEmpty else { return }

        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                self.enqueueSaveObjectIDs(objectIDs)
                if self.isSyncEnabled() { self.scheduleFlush(after: 0) }
                continuation.resume()
            }
        }
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard isNotificationFromOurStack(notification) else { return }

        // Skip saves from inbound sync to avoid sync loops
        if let context = notification.object as? NSManagedObjectContext,
           SyncTransactionAuthor.isInboundSync(context.transactionAuthor) {
            return
        }

        guard let userInfo = notification.userInfo else { return }

        let insertedObjects = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updatedObjects = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deletedObjects = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []

        if insertedObjects.isEmpty, updatedObjects.isEmpty, deletedObjects.isEmpty { return }

        let saveObjectIDs = (insertedObjects.map(\.objectID) + updatedObjects.map(\.objectID))
        let deleteRecordIDs = extractDeletedRecordIDs(from: deletedObjects)

        stateQueue.async { [weak self] in
            guard let self else { return }
            self.enqueueSaveObjectIDs(saveObjectIDs)
            self.enqueueDeleteRecordIDs(deleteRecordIDs)
            if self.isSyncEnabled() {
                self.scheduleFlush(after: self.configuration.debounceInterval)
            }
        }
    }

    private func isNotificationFromOurStack(_ notification: Notification) -> Bool {
        guard let context = notification.object as? NSManagedObjectContext else { return false }
        guard let coordinator = context.persistentStoreCoordinator else { return false }
        return coordinator == persistenceController.container.persistentStoreCoordinator
    }

    private func enqueueSaveObjectIDs(
        _ objectIDs: [NSManagedObjectID],
        previousAttachmentRetryAttempts: [NSManagedObjectID: Int] = [:]
    ) {
        guard !objectIDs.isEmpty else { return }

        let context = persistenceController.newBackgroundContext()
        var records: [CKRecord] = []
        var membershipRecords: [CKRecord] = []
        var membershipDeleteIDs: Set<CKRecord.ID> = []

        context.performAndWait {
            let allCustomPinboardIDs = fetchAllCustomPinboardIDs(in: context)
            let allPrivateCustomPinboardIDs = fetchAllPrivateCustomPinboardIDs(in: context)

            for objectID in objectIDs {
                guard let entityName = objectID.entity.name else { continue }
                guard let object = try? context.existingObject(with: objectID) else { continue }

                if entityName == "ClipItem", let item = object as? ClipItem {
                    if shouldRouteThroughShared(item: item) {
                        enqueuePrivateStaleDeletes(
                            for: item,
                            candidatePinboardIDs: allCustomPinboardIDs
                        )
                        continue
                    }

                    records.append(mapper.mapToRecord(item))

                    let currentCustomPinboardIDs = Set(
                        (item.pinboards ?? [])
                            .filter { !$0.isSystemMarten && !$0.isShared }
                            .map(\.id)
                    )
                    membershipRecords.append(
                        contentsOf: mapPrivatePinboardMemberships(for: item)
                    )
                    for pinboardID in allPrivateCustomPinboardIDs.subtracting(currentCustomPinboardIDs) {
                        membershipDeleteIDs.insert(
                            .membershipID(
                                clipItemID: item.id,
                                pinboardID: pinboardID,
                                zoneID: zoneID
                            )
                        )
                    }
                    continue
                }

                if entityName == "ClipRepresentation", let rep = object as? ClipRepresentation {
                    guard let parent = rep.clipItem else { continue }
                    if shouldRouteThroughShared(item: parent) {
                        enqueueDelete(recordID: .clipRepresentationID(rep.id, zoneID: zoneID))
                        continue
                    }
                    guard let parentID = rep.clipItem?.id else { continue }
                    let record = mapper.mapToRecord(rep, parentItemID: parentID)
                    let previousAttempts = previousAttachmentRetryAttempts[objectID] ?? 0
                    do {
                        try assetSyncManager.attachAssetIfNeededSync(from: rep, to: record)
                    } catch {
                        handleRepresentationAttachmentFailure(
                            objectID: objectID,
                            representationID: rep.id,
                            recordID: record.recordID,
                            previousAttempts: previousAttempts,
                            error: error
                        )
                        continue
                    }
                    records.append(record)
                    continue
                }

                if entityName == "LinkPreview", let preview = object as? LinkPreview {
                    guard let parent = preview.clipItem else { continue }
                    if shouldRouteThroughShared(item: parent) {
                        enqueueDelete(recordID: .linkPreviewID(preview.id, zoneID: zoneID))
                        continue
                    }
                    guard let parentID = preview.clipItem?.id else { continue }
                    records.append(mapper.mapToRecord(preview, parentItemID: parentID))
                    continue
                }

                if entityName == "Pinboard", let pinboard = object as? Pinboard {
                    guard !pinboard.isSystemMarten else { continue }
                    if shouldRouteThroughShared(pinboard: pinboard) {
                        enqueuePrivateStaleDeletes(for: pinboard)
                        continue
                    }
                    records.append(mapper.mapToRecord(pinboard))
                    continue
                }
            }
        }

        let activeMembershipRecordIDs = Set(membershipRecords.map(\.recordID))
        let staleMembershipDeleteIDs = membershipDeleteIDs.subtracting(activeMembershipRecordIDs)

        for record in records + membershipRecords {
            pendingDeletes.remove(record.recordID)
            pendingSaves[record.recordID] = record
            statusByID[record.recordID] = .pending
        }

        enqueueDeleteRecordIDs(staleMembershipDeleteIDs)
    }

    private func handleRepresentationAttachmentFailure(
        objectID: NSManagedObjectID,
        representationID: UUID,
        recordID: CKRecord.ID,
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
                engine: "OutboundSyncEngine",
                representationID: representationID,
                reason: reason
            )
        )

        if nextAttempts >= configuration.maxRetries {
            pendingAssetAttachmentRetries.removeValue(forKey: objectID)
            statusByID[recordID] = .failed
            return
        }

        pendingAssetAttachmentRetries[objectID] = PendingAssetAttachmentRetry(
            recordID: recordID,
            attempts: nextAttempts
        )
        statusByID[recordID] = .pending

        guard isSyncEnabled() else { return }
        guard pendingSaves.isEmpty, pendingDeletes.isEmpty, inFlight == nil else { return }
        scheduleFlush(after: attachmentRetryDelay(forAttempt: nextAttempts))
    }

    private func processPendingAttachmentRetries() {
        guard !pendingAssetAttachmentRetries.isEmpty else { return }

        let retries = pendingAssetAttachmentRetries
        pendingAssetAttachmentRetries.removeAll()

        let previousAttemptsByObjectID = Dictionary(
            uniqueKeysWithValues: retries.map { key, value in
                (key, value.attempts)
            }
        )
        enqueueSaveObjectIDs(
            Array(retries.keys),
            previousAttachmentRetryAttempts: previousAttemptsByObjectID
        )
    }

    private func attachmentRetryDelay(forAttempt attempt: Int) -> TimeInterval {
        configuration.retryBackoff * pow(2.0, Double(max(0, attempt - 1)))
    }

    private func localizedReason(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? String(describing: error) : message
    }

    private func enqueueDeleteRecordIDs(_ recordIDs: Set<CKRecord.ID>) {
        guard !recordIDs.isEmpty else { return }
        for recordID in recordIDs {
            enqueueDelete(recordID: recordID)
        }
    }

    private func extractDeletedRecordIDs(from objects: Set<NSManagedObject>) -> Set<CKRecord.ID> {
        var recordIDs: Set<CKRecord.ID> = []

        for object in objects {
            if let item = object as? ClipItem {
                if shouldRouteThroughShared(item: item) {
                    continue
                }
                recordIDs.insert(.clipItemID(item.id, zoneID: zoneID))
                if let reps = item.representations {
                    for rep in reps {
                        recordIDs.insert(.clipRepresentationID(rep.id, zoneID: zoneID))
                    }
                }
                if let preview = item.linkPreview {
                    recordIDs.insert(.linkPreviewID(preview.id, zoneID: zoneID))
                }
                if let pinboards = item.pinboards {
                    for pinboard in pinboards where !pinboard.isSystemMarten {
                        recordIDs.insert(
                            .membershipID(
                                clipItemID: item.id,
                                pinboardID: pinboard.id,
                                zoneID: zoneID
                            )
                        )
                    }
                }
            } else if let rep = object as? ClipRepresentation {
                if let parent = rep.clipItem, shouldRouteThroughShared(item: parent) {
                    continue
                }
                recordIDs.insert(.clipRepresentationID(rep.id, zoneID: zoneID))
            } else if let preview = object as? LinkPreview {
                if let parent = preview.clipItem, shouldRouteThroughShared(item: parent) {
                    continue
                }
                recordIDs.insert(.linkPreviewID(preview.id, zoneID: zoneID))
            } else if let pinboard = object as? Pinboard {
                guard !pinboard.isSystemMarten else { continue }
                if shouldRouteThroughShared(pinboard: pinboard) {
                    continue
                }
                recordIDs.insert(.pinboardID(pinboard.id, zoneID: zoneID))

                if let items = pinboard.items {
                    for item in items {
                        recordIDs.insert(
                            .membershipID(
                                clipItemID: item.id,
                                pinboardID: pinboard.id,
                                zoneID: zoneID
                            )
                        )
                    }
                }
            }
        }

        return recordIDs
    }

    private func fetchAllCustomPinboardIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemMarten == NO")
        let pinboards = (try? context.fetch(request)) ?? []
        return Set(pinboards.map(\.id))
    }

    private func fetchAllPrivateCustomPinboardIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = Pinboard.fetchRequest()
        request.predicate = NSPredicate(format: "isSystemMarten == NO AND shareMetadata == nil")
        let pinboards = (try? context.fetch(request)) ?? []
        return Set(pinboards.map(\.id))
    }

    private func mapPrivatePinboardMemberships(for item: ClipItem) -> [CKRecord] {
        guard let pinboards = item.pinboards else { return [] }

        return pinboards.compactMap { pinboard -> CKRecord? in
            guard !pinboard.isSystemMarten, !pinboard.isShared else { return nil }
            let membershipID = CKRecord.ID.deterministicMembershipUUID(
                clipItemID: item.id,
                pinboardID: pinboard.id
            )
            let membership = CloudRecordMapper.PinboardMembershipData(
                id: membershipID,
                clipItemID: item.id,
                pinboardID: pinboard.id
            )
            return mapper.mapToRecord(membership)
        }
    }

    private func shouldRouteThroughShared(item: ClipItem) -> Bool {
        guard let shareZoneRegistry else { return false }
        let routing = shareZoneRegistry.routingInfo(for: item)
        return routing.database != .privateDB || routing.zoneID != zoneID
    }

    private func shouldRouteThroughShared(pinboard: Pinboard) -> Bool {
        guard let shareZoneRegistry else { return false }
        let routing = shareZoneRegistry.routingInfo(for: pinboard)
        return routing.database != .privateDB || routing.zoneID != zoneID
    }

    private func enqueuePrivateStaleDeletes(for pinboard: Pinboard) {
        enqueueDelete(recordID: .pinboardID(pinboard.id, zoneID: zoneID))
        guard let items = pinboard.items else { return }
        for item in items {
            enqueueDelete(
                recordID: .membershipID(
                    clipItemID: item.id,
                    pinboardID: pinboard.id,
                    zoneID: zoneID
                )
            )
        }
    }

    private func enqueuePrivateStaleDeletes(for item: ClipItem, candidatePinboardIDs: Set<UUID>) {
        enqueueDelete(recordID: .clipItemID(item.id, zoneID: zoneID))
        if let representations = item.representations {
            for representation in representations {
                enqueueDelete(recordID: .clipRepresentationID(representation.id, zoneID: zoneID))
            }
        }
        if let preview = item.linkPreview {
            enqueueDelete(recordID: .linkPreviewID(preview.id, zoneID: zoneID))
        }
        for pinboardID in candidatePinboardIDs {
            enqueueDelete(
                recordID: .membershipID(
                    clipItemID: item.id,
                    pinboardID: pinboardID,
                    zoneID: zoneID
                )
            )
        }
    }

    private func enqueueDelete(recordID: CKRecord.ID) {
        pendingSaves.removeValue(forKey: recordID)
        pendingDeletes.insert(recordID)
        statusByID[recordID] = .pending
    }

    private func scheduleFlush(after delay: TimeInterval) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.flushTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.beginFlush()
            }
            self.flushTimer = work
            self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func beginFlush() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.inFlight == nil else { return }

            self.processPendingAttachmentRetries()

            guard !self.pendingSaves.isEmpty || !self.pendingDeletes.isEmpty else { return }

            let work = WorkItem(
                saveRecordsByID: self.pendingSaves,
                deleteIDs: self.pendingDeletes,
                attempts: 0
            )
            self.pendingSaves = [:]
            self.pendingDeletes = []
            self.inFlight = work
            for id in work.saveRecordsByID.keys {
                self.statusByID[id] = .uploading
            }
            for id in work.deleteIDs {
                self.statusByID[id] = .uploading
            }

            Task { [weak self] in
                await self?.process(work: work)
            }
        }
    }

    private func process(work: WorkItem) async {
        guard isSyncEnabled() else {
            stateQueue.async { [weak self] in
                guard let self else { return }
                self.requeueForRetry(work: work)
                self.inFlight = nil
            }
            return
        }

        let orderedSaveRecords = CloudRecordUploadOrdering.sortedForUpload(work.saveRecordsByID.values)
        let saveChunks = orderedSaveRecords.chunked(maxSize: configuration.maxRecordsPerBatch)
        let deleteChunks = Array(work.deleteIDs).chunked(maxSize: configuration.maxRecordsPerBatch)

        var failedSaves: [CKRecord.ID: Error] = [:]
        var failedDeletes: [CKRecord.ID: Error] = [:]

        for chunk in saveChunks {
            let result = await database.modifyRecords(saving: chunk, deleting: [])
            failedSaves.merge(result.saveErrors) { _, new in new }
            if let opError = result.operationError {
                if result.saveErrors.isEmpty {
                    for record in chunk {
                        failedSaves[record.recordID] = opError
                    }
                }
                if let classified = classifyOperationError(opError), !classified.isRetryable {
                    stateQueue.async { [weak self] in
                        self?.markFailed(records: chunk.map { $0.recordID }, deletes: [])
                        self?.completeCurrentFlush()
                    }
                    return
                }
            }
        }

        for chunk in deleteChunks {
            let result = await database.modifyRecords(saving: [], deleting: chunk)
            failedDeletes.merge(result.deleteErrors) { _, new in new }
            if let opError = result.operationError {
                if result.deleteErrors.isEmpty {
                    for recordID in chunk {
                        failedDeletes[recordID] = opError
                    }
                }
                if let classified = classifyOperationError(opError), !classified.isRetryable {
                    stateQueue.async { [weak self] in
                        self?.markFailed(records: [], deletes: chunk)
                        self?.completeCurrentFlush()
                    }
                    return
                }
            }
        }

        if failedSaves.isEmpty, failedDeletes.isEmpty {
            stateQueue.async { [weak self] in
                guard let self else { return }
                for id in work.saveRecordsByID.keys {
                    self.statusByID[id] = .uploaded
                }
                for id in work.deleteIDs {
                    self.statusByID[id] = .uploaded
                }
                self.completeCurrentFlush()
            }
            return
        }

        let resolvedByID = await resolveConflictsIfNeeded(work: work, failedSaves: failedSaves)

        var retryWork = WorkItem(saveRecordsByID: [:], deleteIDs: [], attempts: work.attempts + 1)
        for (recordID, error) in failedSaves {
            if resolvedByID[recordID] != nil {
                retryWork.saveRecordsByID[recordID] = resolvedByID[recordID]
                continue
            }
            if shouldRetry(error: error, attempts: retryWork.attempts) {
                if let record = work.saveRecordsByID[recordID] {
                    retryWork.saveRecordsByID[recordID] = record
                }
            } else {
                stateQueue.async { [weak self] in
                    self?.statusByID[recordID] = .failed
                }
            }
        }

        for (recordID, error) in failedDeletes {
            if shouldRetry(error: error, attempts: retryWork.attempts) {
                retryWork.deleteIDs.insert(recordID)
            } else {
                stateQueue.async { [weak self] in
                    self?.statusByID[recordID] = .failed
                }
            }
        }

        stateQueue.async { [weak self] in
            guard let self else { return }
            self.inFlight = nil
            if retryWork.saveRecordsByID.isEmpty && retryWork.deleteIDs.isEmpty {
                self.resumeFlushCompletionContinuations()
                self.scheduleFlushIfPending()
                return
            }
            let delay = self.retryDelay(
                for: failedSaves.merged(with: failedDeletes), attempt: retryWork.attempts)
            self.pendingSaves.merge(retryWork.saveRecordsByID) { _, new in new }
            self.pendingDeletes.formUnion(retryWork.deleteIDs)
            self.resumeFlushCompletionContinuations()
            self.scheduleFlush(after: delay)
        }
    }

    private func resolveConflictsIfNeeded(
        work: WorkItem,
        failedSaves: [CKRecord.ID: Error]
    ) async -> [CKRecord.ID: CKRecord] {
        var resolvedByID: [CKRecord.ID: CKRecord] = [:]
        for (recordID, error) in failedSaves {
            guard let ckError = error as? CKError, ckError.code == .serverRecordChanged else {
                continue
            }
            guard
                let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey]
                    as? CKRecord
            else { continue }
            guard let localRecord = work.saveRecordsByID[recordID] else { continue }
            do {
                let resolved = try await conflictResolver.resolve(
                    localRecord: localRecord, serverRecord: serverRecord)
                resolvedByID[recordID] = resolved
            } catch {
                continue
            }
        }
        return resolvedByID
    }

    private func classifyOperationError(_ error: Error) -> CloudKitSyncError? {
        CloudKitErrorClassifier.classify(error)
    }

    private func shouldRetry(error: Error, attempts: Int) -> Bool {
        if attempts >= configuration.maxRetries { return false }
        if CloudKitErrorClassifier.isTransient(error) { return true }
        let classified = CloudKitErrorClassifier.classify(error)
        return classified.isRetryable
    }

    private func retryDelay(for errors: [CKRecord.ID: Error], attempt: Int) -> TimeInterval {
        let maxSuggested = errors.values.compactMap {
            CloudKitErrorClassifier.retryAfterDelay(for: $0)
        }.max()
        let exponential = configuration.retryBackoff * pow(2.0, Double(max(0, attempt - 1)))
        if let maxSuggested {
            return max(maxSuggested, exponential)
        }
        return exponential
    }

    private func markFailed(records: [CKRecord.ID], deletes: [CKRecord.ID]) {
        for id in records {
            statusByID[id] = .failed
        }
        for id in deletes {
            statusByID[id] = .failed
        }
    }

    private func completeCurrentFlush() {
        self.inFlight = nil
        resumeFlushCompletionContinuations()
        self.scheduleFlushIfPending()
    }

    private func requeueForRetry(work: WorkItem) {
        pendingSaves.merge(work.saveRecordsByID) { _, new in new }
        pendingDeletes.formUnion(work.deleteIDs)
        resumeFlushCompletionContinuations()
        if isSyncEnabled() {
            scheduleFlush(after: configuration.debounceInterval)
        }
    }

    private func resumeFlushCompletionContinuations() {
        guard !flushCompletionContinuations.isEmpty else { return }
        let continuations = flushCompletionContinuations
        flushCompletionContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
    }

    private func scheduleFlushIfPending() {
        if !pendingSaves.isEmpty || !pendingDeletes.isEmpty {
            scheduleFlush(after: 0)
        }
    }
}

extension Sequence {
    fileprivate func chunked(maxSize: Int) -> [[Element]] {
        var result: [[Element]] = []
        var current: [Element] = []
        current.reserveCapacity(maxSize)

        for element in self {
            current.append(element)
            if current.count == maxSize {
                result.append(current)
                current = []
                current.reserveCapacity(maxSize)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}

extension Dictionary where Value == Error {
    fileprivate func merged(with other: [Key: Value]) -> [Key: Value] {
        var merged = self
        merged.merge(other) { _, new in new }
        return merged
    }
}
