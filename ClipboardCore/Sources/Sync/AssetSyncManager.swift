import CloudKit
import Combine
import CryptoKit
import Foundation

public enum AssetSyncError: Error, Equatable {
    case missingLocalAsset
    case missingRemoteAsset
    case assetTooLarge(bytes: Int64, limit: Int64)
    case totalAssetBudgetExceeded(bytes: Int64, limit: Int64)
    case invalidAssetFilename
    case fileReadFailed
    case cloudKitError
}

public protocol CloudKitRecordsModifying: AnyObject, Sendable {
    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID]?,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        perRecordProgress: (@Sendable (String, Double) -> Void)?
    ) async throws -> [CKRecord]
}

public protocol CloudKitRecordsFetching: AnyObject, Sendable {
    func fetchRecord(withID recordID: CKRecord.ID, desiredKeys: [String]?) async throws -> CKRecord
}

extension CKDatabase: CloudKitRecordsModifying {}
extension CKDatabase: CloudKitRecordsFetching {}

public final class AssetSyncManager {
    public struct Configuration: Sendable {
        public var perAssetLimitBytes: Int64
        public var totalLimitBytes: Int64
        public var maxRetryCount: Int
        public var initialRetryDelayNanoseconds: UInt64

        public init(
            perAssetLimitBytes: Int64 = 50 * 1024 * 1024,
            totalLimitBytes: Int64 = 1024 * 1024 * 1024,
            maxRetryCount: Int = 2,
            initialRetryDelayNanoseconds: UInt64 = 250_000_000
        ) {
            self.perAssetLimitBytes = perAssetLimitBytes
            self.totalLimitBytes = totalLimitBytes
            self.maxRetryCount = maxRetryCount
            self.initialRetryDelayNanoseconds = initialRetryDelayNanoseconds
        }
    }

    public enum Direction: Sendable {
        case upload
        case download
    }

    public struct ProgressUpdate: Sendable, Equatable {
        public let direction: Direction
        public let recordName: String
        public let fieldKey: String
        public let fractionCompleted: Double
    }

    private actor AssetCache {
        var assetRefByHash: [String: UUID] = [:]
        var bytesUploadedThisSession: Int64 = 0
        var bytesDownloadedThisSession: Int64 = 0
        var assetRefByRemoteKey: [RemoteKey: UUID] = [:]

        struct RemoteKey: Hashable, Sendable {
            let recordName: String
            let fieldKey: String
        }

        func resetBudgets() {
            bytesUploadedThisSession = 0
            bytesDownloadedThisSession = 0
        }

        func cachedAssetRef(for remoteKey: RemoteKey) -> UUID? {
            assetRefByRemoteKey[remoteKey]
        }

        func setCachedAssetRef(_ assetRef: UUID, for remoteKey: RemoteKey) {
            assetRefByRemoteKey[remoteKey] = assetRef
        }

        func cachedAssetRef(forHash hash: String) -> UUID? {
            assetRefByHash[hash]
        }

        func setCachedAssetRef(_ assetRef: UUID, forHash hash: String) {
            assetRefByHash[hash] = assetRef
        }

        func checkAndAddBytes(_ sizeBytes: Int64, direction: Direction, limitBytes: Int64) throws {
            switch direction {
            case .upload:
                let updated = bytesUploadedThisSession + sizeBytes
                if updated > limitBytes {
                    throw AssetSyncError.totalAssetBudgetExceeded(bytes: updated, limit: limitBytes)
                }
                bytesUploadedThisSession = updated
            case .download:
                let updated = bytesDownloadedThisSession + sizeBytes
                if updated > limitBytes {
                    throw AssetSyncError.totalAssetBudgetExceeded(bytes: updated, limit: limitBytes)
                }
                bytesDownloadedThisSession = updated
            }
        }
    }

    private let assetStore: AssetStore
    private let fileManager: FileManager
    private let configuration: Configuration
    private let cache = AssetCache()
    private let progressSubject = PassthroughSubject<ProgressUpdate, Never>()

    public var progressPublisher: AnyPublisher<ProgressUpdate, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    public init(
        assetStore: AssetStore = .shared,
        fileManager: FileManager = .default,
        configuration: Configuration = Configuration()
    ) {
        self.assetStore = assetStore
        self.fileManager = fileManager
        self.configuration = configuration
    }

    public func resetSessionBudgets() async {
        await cache.resetBudgets()
    }

    public func attachAssetIfNeeded(from representation: ClipRepresentation, to record: CKRecord)
        async throws
    {
        guard let assetRef = representation.assetRef else {
            return
        }

        let fileURL = assetStore.urlForAsset(assetRef, fileExtension: representation.fileExtension)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AssetSyncError.missingLocalAsset
        }

        let sizeBytes = try fileSizeBytes(at: fileURL)
        try validateAssetSize(sizeBytes)
        try await validateTotalBudget(direction: .upload, adding: sizeBytes)

        let hash = try sha256HexOfFile(at: fileURL)
        if await cache.cachedAssetRef(forHash: hash) == nil {
            await cache.setCachedAssetRef(assetRef, forHash: hash)
        }

        let asset = CKAsset(fileURL: fileURL)
        record.setAsset(asset, for: ClipRepresentationField.asset.rawValue)
    }

    public func upload(
        records: [CKRecord],
        in database: CloudKitRecordsModifying,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .changedKeys
    ) async throws -> [CKRecord] {
        try Task.checkCancellation()

        return try await database.modifyRecords(
            saving: records,
            deleting: nil,
            savePolicy: savePolicy,
            perRecordProgress: { [progressSubject] recordName, fraction in
                progressSubject.send(
                    ProgressUpdate(
                        direction: .upload,
                        recordName: recordName,
                        fieldKey: ClipRepresentationField.asset.rawValue,
                        fractionCompleted: fraction
                    )
                )
            }
        )
    }

    public func downloadAssetOnDemand(
        recordID: CKRecord.ID,
        fieldKey: String = ClipRepresentationField.asset.rawValue,
        suggestedFileExtension: String? = nil,
        from database: CloudKitRecordsFetching
    ) async throws -> UUID {
        try Task.checkCancellation()

        let record = try await fetchWithRetry(
            recordID: recordID, desiredKeys: [fieldKey], from: database)
        return try await storeAsset(
            from: record, recordID: recordID, fieldKey: fieldKey,
            suggestedFileExtension: suggestedFileExtension)
    }

    public func applyDownloadedAssetIfPresent(
        from record: CKRecord,
        to representation: ClipRepresentation,
        fieldKey: String = ClipRepresentationField.asset.rawValue
    ) async throws {
        guard representation.assetRef == nil else {
            return
        }

        guard let asset = record.asset(for: fieldKey), let fileURL = asset.fileURL else {
            return
        }

        let recordID = record.recordID
        let storedRef = try await storeAsset(
            assetFileURL: fileURL,
            remoteRecordID: recordID,
            fieldKey: fieldKey,
            suggestedFileExtension: representation.fileExtension
        )
        representation.assetRef = storedRef
    }

    public func cleanupOrphanedAssets(
        referencedAssetRefs: Set<UUID>,
        policy: RetentionPolicy,
        now: Date = Date()
    ) throws -> Int {
        guard let retentionDate = policy.retentionDate(reference: now) else {
            return 0
        }

        let urls = try fileManager.contentsOfDirectory(
            at: assetStore.urlForAsset(UUID()).deletingLastPathComponent(),
            includingPropertiesForKeys: [
                URLResourceKey.isRegularFileKey,
                URLResourceKey.contentModificationDateKey,
                URLResourceKey.creationDateKey,
            ],
            options: [.skipsHiddenFiles]
        )

        var deleted = 0
        for url in urls {
            let values = try url.resourceValues(forKeys: [
                URLResourceKey.isRegularFileKey,
                URLResourceKey.contentModificationDateKey,
                URLResourceKey.creationDateKey,
            ])
            guard values.isRegularFile == true else { continue }

            let (assetRef, _) = try parseAssetFilename(url.lastPathComponent)
            guard !referencedAssetRefs.contains(assetRef) else { continue }

            let date = values.contentModificationDate ?? values.creationDate ?? now
            guard date < retentionDate else { continue }

            try? fileManager.removeItem(at: url)
            deleted += 1
        }

        return deleted
    }

    private func validateAssetSize(_ sizeBytes: Int64) throws {
        if sizeBytes > configuration.perAssetLimitBytes {
            throw AssetSyncError.assetTooLarge(
                bytes: sizeBytes, limit: configuration.perAssetLimitBytes)
        }
    }

    private func validateTotalBudget(direction: Direction, adding sizeBytes: Int64) async throws {
        try await cache.checkAndAddBytes(
            sizeBytes, direction: direction, limitBytes: configuration.totalLimitBytes)
    }

    private func storeAsset(
        from record: CKRecord,
        recordID: CKRecord.ID,
        fieldKey: String,
        suggestedFileExtension: String?
    ) async throws -> UUID {
        guard let asset = record.asset(for: fieldKey), let fileURL = asset.fileURL else {
            throw AssetSyncError.missingRemoteAsset
        }

        return try await storeAsset(
            assetFileURL: fileURL,
            remoteRecordID: recordID,
            fieldKey: fieldKey,
            suggestedFileExtension: suggestedFileExtension
        )
    }

    private func storeAsset(
        assetFileURL: URL,
        remoteRecordID: CKRecord.ID,
        fieldKey: String,
        suggestedFileExtension: String?
    ) async throws -> UUID {
        try Task.checkCancellation()

        let remoteKey = AssetCache.RemoteKey(
            recordName: remoteRecordID.recordName, fieldKey: fieldKey)
        if let cached = await cache.cachedAssetRef(for: remoteKey) {
            return cached
        }

        let sizeBytes = try fileSizeBytes(at: assetFileURL)
        try validateAssetSize(sizeBytes)
        try await validateTotalBudget(direction: .download, adding: sizeBytes)

        let hash = try sha256HexOfFile(at: assetFileURL)
        if let existingRef = await cache.cachedAssetRef(forHash: hash) {
            await cache.setCachedAssetRef(existingRef, for: remoteKey)
            return existingRef
        }

        let newAssetRef = UUID()
        let destination = assetStore.urlForAsset(newAssetRef, fileExtension: suggestedFileExtension)

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: assetFileURL, to: destination)

        await cache.setCachedAssetRef(newAssetRef, forHash: hash)
        await cache.setCachedAssetRef(newAssetRef, for: remoteKey)
        progressSubject.send(
            ProgressUpdate(
                direction: .download,
                recordName: remoteRecordID.recordName,
                fieldKey: fieldKey,
                fractionCompleted: 1.0
            )
        )

        return newAssetRef
    }

    private func fetchWithRetry(
        recordID: CKRecord.ID,
        desiredKeys: [String]?,
        from database: CloudKitRecordsFetching
    ) async throws -> CKRecord {
        var attempt = 0
        var delay = configuration.initialRetryDelayNanoseconds

        while true {
            try Task.checkCancellation()
            do {
                return try await database.fetchRecord(withID: recordID, desiredKeys: desiredKeys)
            } catch let error as CKError {
                attempt += 1
                if attempt > configuration.maxRetryCount {
                    throw error
                }

                if error.code == .requestRateLimited,
                    let retry = error.userInfo[CKErrorRetryAfterKey] as? TimeInterval
                {
                    let nanos = UInt64(retry * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanos)
                    continue
                }

                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 5_000_000_000)
            } catch {
                attempt += 1
                if attempt > configuration.maxRetryCount {
                    throw error
                }
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 5_000_000_000)
            }
        }
    }

    private func fileSizeBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func parseAssetFilename(_ filename: String) throws -> (UUID, String?) {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let assetRef = UUID(uuidString: name) else {
            throw AssetSyncError.invalidAssetFilename
        }
        return (assetRef, ext.isEmpty ? nil : ext)
    }

    private func sha256HexOfFile(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            throw AssetSyncError.fileReadFailed
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension CKDatabase {
    public func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID]?,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        perRecordProgress: (@Sendable (String, Double) -> Void)?
    ) async throws -> [CKRecord] {
        var operation: CKModifyRecordsOperation?
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    let op = CKModifyRecordsOperation(
                        recordsToSave: records, recordIDsToDelete: recordIDs)
                    operation = op
                    op.savePolicy = savePolicy
                    var savedRecords: [CKRecord] = []

                    if let perRecordProgress {
                        op.perRecordProgressBlock = { record, progress in
                            perRecordProgress(record.recordID.recordName, progress)
                        }
                    }

                    op.perRecordSaveBlock = { _, result in
                        if case .success(let record) = result {
                            savedRecords.append(record)
                        }
                    }

                    op.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            continuation.resume(returning: savedRecords)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    self.add(op)
                }
            },
            onCancel: {
                operation?.cancel()
            })
    }

    public func fetchRecord(withID recordID: CKRecord.ID, desiredKeys: [String]?) async throws
        -> CKRecord
    {
        var operation: CKFetchRecordsOperation?
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<CKRecord, Error>) in
                    let op = CKFetchRecordsOperation(recordIDs: [recordID])
                    operation = op
                    op.desiredKeys = desiredKeys

                    var fetchedRecord: CKRecord?
                    var perRecordError: Error?
                    op.perRecordResultBlock = { _, result in
                        switch result {
                        case .success(let record):
                            fetchedRecord = record
                        case .failure(let error):
                            perRecordError = error
                        }
                    }

                    op.fetchRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            if let perRecordError {
                                continuation.resume(throwing: perRecordError)
                                return
                            }
                            guard let fetchedRecord else {
                                continuation.resume(throwing: CKError(.unknownItem))
                                return
                            }
                            continuation.resume(returning: fetchedRecord)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    self.add(op)
                }
            },
            onCancel: {
                operation?.cancel()
            })
    }
}
