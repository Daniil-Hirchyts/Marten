import CloudKit
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
        for key in localRecord.allKeys() {
            serverRecord[key] = localRecord[key]
        }
        return serverRecord
    }
}

public final class OutboundSyncEngine {
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

    private let persistenceController: PersistenceController
    private let database: OutboundCloudDatabase
    private let zoneID: CKRecordZone.ID
    private let mapper: CloudRecordMapper
    private let configuration: Configuration
    private let isSyncEnabled: @Sendable () -> Bool
    private let conflictResolver: OutboundConflictResolving

    private let stateQueue = DispatchQueue(label: "com.paste.sync.outbound", qos: .utility)
    private var saveObserver: NSObjectProtocol?
    private var flushTimer: DispatchWorkItem?
    private var pendingSaves: [CKRecord.ID: CKRecord] = [:]
    private var pendingDeletes: Set<CKRecord.ID> = []
    private var statusByID: [CKRecord.ID: RecordStatus] = [:]
    private var inFlight: WorkItem?
    private var flushCompletionContinuation: CheckedContinuation<Void, Never>?

    public init(
        persistenceController: PersistenceController,
        database: OutboundCloudDatabase,
        zoneID: CKRecordZone.ID,
        configuration: Configuration = Configuration(),
        isSyncEnabled: @escaping @Sendable () -> Bool = { true },
        conflictResolver: OutboundConflictResolving = DefaultOutboundConflictResolver()
    ) {
        self.persistenceController = persistenceController
        self.database = database
        self.zoneID = zoneID
        self.mapper = CloudRecordMapper(zoneID: zoneID)
        self.configuration = configuration
        self.isSyncEnabled = isSyncEnabled
        self.conflictResolver = conflictResolver
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
                self.flushCompletionContinuation = continuation
                self.scheduleFlush(after: 0)
            }
        }
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard isNotificationFromOurStack(notification) else { return }

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

    private func enqueueSaveObjectIDs(_ objectIDs: [NSManagedObjectID]) {
        guard !objectIDs.isEmpty else { return }

        let context = persistenceController.newBackgroundContext()
        var records: [CKRecord] = []

        context.performAndWait {
            for objectID in objectIDs {
                guard let entityName = objectID.entity.name else { continue }
                guard let object = try? context.existingObject(with: objectID) else { continue }

                if entityName == "ClipItem", let item = object as? ClipItem {
                    records.append(mapper.mapToRecord(item))
                    continue
                }

                if entityName == "ClipRepresentation", let rep = object as? ClipRepresentation {
                    guard let parentID = rep.clipItem?.id else { continue }
                    records.append(mapper.mapToRecord(rep, parentItemID: parentID))
                    continue
                }

                if entityName == "LinkPreview", let preview = object as? LinkPreview {
                    guard let parentID = preview.clipItem?.id else { continue }
                    records.append(mapper.mapToRecord(preview, parentItemID: parentID))
                    continue
                }

                if entityName == "Pinboard", let pinboard = object as? Pinboard {
                    records.append(mapper.mapToRecord(pinboard))
                    continue
                }
            }
        }

        for record in records {
            pendingDeletes.remove(record.recordID)
            pendingSaves[record.recordID] = record
            statusByID[record.recordID] = .pending
        }
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
                recordIDs.insert(.clipItemID(item.id, zoneID: zoneID))
                if let reps = item.representations {
                    for rep in reps {
                        recordIDs.insert(.clipRepresentationID(rep.id, zoneID: zoneID))
                    }
                }
                if let preview = item.linkPreview {
                    recordIDs.insert(.linkPreviewID(preview.id, zoneID: zoneID))
                }
            } else if let rep = object as? ClipRepresentation {
                recordIDs.insert(.clipRepresentationID(rep.id, zoneID: zoneID))
            } else if let preview = object as? LinkPreview {
                recordIDs.insert(.linkPreviewID(preview.id, zoneID: zoneID))
            } else if let pinboard = object as? Pinboard {
                recordIDs.insert(.pinboardID(pinboard.id, zoneID: zoneID))
            }
        }

        return recordIDs
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

        let saveChunks = work.saveRecordsByID.values.chunked(
            maxSize: configuration.maxRecordsPerBatch)
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
                if let cont = self.flushCompletionContinuation {
                    self.flushCompletionContinuation = nil
                    cont.resume()
                }
                self.scheduleFlushIfPending()
                return
            }
            let delay = self.retryDelay(
                for: failedSaves.merged(with: failedDeletes), attempt: retryWork.attempts)
            self.pendingSaves.merge(retryWork.saveRecordsByID) { _, new in new }
            self.pendingDeletes.formUnion(retryWork.deleteIDs)
            if let cont = self.flushCompletionContinuation {
                self.flushCompletionContinuation = nil
                cont.resume()
            }
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
        if let cont = self.flushCompletionContinuation {
            self.flushCompletionContinuation = nil
            cont.resume()
        }
        self.scheduleFlushIfPending()
    }

    private func requeueForRetry(work: WorkItem) {
        pendingSaves.merge(work.saveRecordsByID) { _, new in new }
        pendingDeletes.formUnion(work.deleteIDs)
        if let cont = flushCompletionContinuation {
            flushCompletionContinuation = nil
            cont.resume()
        }
        if isSyncEnabled() {
            scheduleFlush(after: configuration.debounceInterval)
        }
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
