import CloudKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

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
    public struct PreloadedAsset: Sendable {
        public let data: Data
        public let fileExtension: String?

        public init(data: Data, fileExtension: String?) {
            self.data = data
            self.fileExtension = fileExtension
        }
    }

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
        let fileURL: URL

        if let assetRef = representation.assetRef {
            guard
                let url = assetStore.existingURLForAsset(
                    assetRef,
                    fileExtension: representation.fileExtension
                )
            else {
                throw AssetSyncError.missingLocalAsset
            }
            applyResolvedFileExtension(from: url, to: representation)
            fileURL = url
        } else if let data = representation.binaryData, !data.isEmpty {
            // binaryData is a local-only field with no CloudKit mapping.
            // Migrate it to AssetStore so it can be uploaded as a CKAsset and
            // received correctly on other platforms.
            let fileExtension = normalizedFileExtension(representation.fileExtension)
            let newRef = try assetStore.store(data: data, fileExtension: fileExtension)
            representation.assetRef = newRef
            representation.fileExtension = fileExtension
            fileURL = assetStore.urlForAsset(newRef, fileExtension: fileExtension)
        } else {
            return
        }

        let sizeBytes = try fileSizeBytes(at: fileURL)
        try validateAssetSize(sizeBytes)
        try await validateTotalBudget(direction: .upload, adding: sizeBytes)

        let hash = try sha256HexOfFile(at: fileURL)
        if let assetRef = representation.assetRef,
           await cache.cachedAssetRef(forHash: hash) == nil {
            await cache.setCachedAssetRef(assetRef, forHash: hash)
        }

        let asset = CKAsset(fileURL: fileURL)
        record.setAsset(asset, for: ClipRepresentationField.asset.rawValue)
    }

    /// Synchronous variant used from Core Data `performAndWait` call sites.
    public func attachAssetIfNeededSync(
        from representation: ClipRepresentation,
        to record: CKRecord
    ) throws {
        let fileURL: URL

        if let assetRef = representation.assetRef {
            guard
                let url = assetStore.existingURLForAsset(
                    assetRef,
                    fileExtension: representation.fileExtension
                )
            else {
                throw AssetSyncError.missingLocalAsset
            }
            applyResolvedFileExtension(from: url, to: representation)
            fileURL = url
        } else if let data = representation.binaryData, !data.isEmpty {
            // binaryData is a local-only field with no CloudKit mapping.
            // Migrate it to AssetStore so it can be uploaded as a CKAsset and
            // received correctly on other platforms.
            let fileExtension = normalizedFileExtension(representation.fileExtension)
            let newRef = try assetStore.store(data: data, fileExtension: fileExtension)
            representation.assetRef = newRef
            representation.fileExtension = fileExtension
            fileURL = assetStore.urlForAsset(newRef, fileExtension: fileExtension)
        } else {
            return
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
        if let existingRef = representation.assetRef {
            if let existingURL = assetStore.existingURLForAsset(
                existingRef,
                fileExtension: representation.fileExtension
            ) {
                applyResolvedFileExtension(from: existingURL, to: representation)
                return
            }
            // File is missing despite assetRef being set — fall through to re-download.
        }

        guard let asset = record.asset(for: fieldKey), let fileURL = asset.fileURL else {
            return
        }

        let recordID = record.recordID
        let inferredExtension = inferredFileExtension(
            existingFileExtension: representation.fileExtension,
            assetFileURL: fileURL,
            uti: representation.uti
        )
        let storedRef = try await storeAsset(
            assetFileURL: fileURL,
            remoteRecordID: recordID,
            fieldKey: fieldKey,
            suggestedFileExtension: inferredExtension
        )
        representation.assetRef = storedRef
        representation.fileExtension = inferredExtension
    }

    /// Synchronous variant used from Core Data `performAndWait` call sites.
    ///
    /// - Parameter preloadedAssetData: Asset data eagerly read during the CloudKit fetch
    ///   callback, used as fallback when the CKAsset temp file is no longer available.
    public func applyDownloadedAssetIfPresentSync(
        from record: CKRecord,
        to representation: ClipRepresentation,
        fieldKey: String = ClipRepresentationField.asset.rawValue,
        preloadedAssetData: PreloadedAsset? = nil
    ) throws {
        if let existingRef = representation.assetRef {
            if let existingURL = assetStore.existingURLForAsset(
                existingRef,
                fileExtension: representation.fileExtension
            ) {
                applyResolvedFileExtension(from: existingURL, to: representation)
                return
            }
            // File is missing despite assetRef being set — fall through to re-download.
        }

        let data: Data
        let inferredExtension: String?

        if let asset = record.asset(for: fieldKey), let fileURL = asset.fileURL,
           let fileData = try? Data(contentsOf: fileURL)
        {
            data = fileData
            inferredExtension = inferredFileExtension(
                existingFileExtension: representation.fileExtension,
                assetFileURL: fileURL
            )
        } else if let preloaded = preloadedAssetData {
            data = preloaded.data
            inferredExtension = preloaded.fileExtension
                ?? normalizedFileExtension(representation.fileExtension)
        } else {
            return
        }

        representation.assetRef = try assetStore.store(data: data, fileExtension: inferredExtension)
        representation.fileExtension = inferredExtension
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

    private func normalizedFileExtension(_ fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        let normalized = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func inferredFileExtension(
        existingFileExtension: String?,
        assetFileURL: URL,
        uti: String? = nil
    ) -> String? {
        if let normalized = normalizedFileExtension(existingFileExtension), normalized.count < 10 {
            return normalized
        }

        if let uti = uti, let utType = UTType(uti), let ext = utType.preferredFilenameExtension {
            return ext
        }

        let pathExt = normalizedFileExtension(assetFileURL.pathExtension)
        if let pathExt = pathExt, pathExt.count < 10 {
            return pathExt
        }

        return nil
    }

    private func applyResolvedFileExtension(from fileURL: URL, to representation: ClipRepresentation) {
        let resolvedExtension = inferredFileExtension(
            existingFileExtension: representation.fileExtension,
            assetFileURL: fileURL
        )

        if representation.fileExtension != resolvedExtension {
            representation.fileExtension = resolvedExtension
        }
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
        let modifyOperation = CKModifyRecordsOperation(
            recordsToSave: records,
            recordIDsToDelete: recordIDs
        )
        let continuationState = CloudKitOperationContinuation<[CKRecord]>()

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    continuationState.install(continuation)
                    modifyOperation.savePolicy = savePolicy
                    var savedRecords: [CKRecord] = []

                    if let perRecordProgress {
                        modifyOperation.perRecordProgressBlock = { record, progress in
                            perRecordProgress(record.recordID.recordName, progress)
                        }
                    }

                    modifyOperation.perRecordSaveBlock = { _, result in
                        if case .success(let record) = result {
                            savedRecords.append(record)
                        }
                    }

                    modifyOperation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            continuationState.resume(with: .success(savedRecords))
                        case .failure(let error):
                            continuationState.resume(with: .failure(error))
                        }
                    }

                    if Task.isCancelled {
                        modifyOperation.cancel()
                        continuationState.resume(with: .failure(CancellationError()))
                        return
                    }

                    self.add(modifyOperation)
                }
            },
            onCancel: {
                modifyOperation.cancel()
                continuationState.resume(with: .failure(CancellationError()))
            })
    }

    public func fetchRecord(withID recordID: CKRecord.ID, desiredKeys: [String]?) async throws
        -> CKRecord
    {
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        let continuationState = CloudKitOperationContinuation<CKRecord>()

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<CKRecord, Error>) in
                    continuationState.install(continuation)
                    fetchOperation.desiredKeys = desiredKeys

                    var fetchedRecord: CKRecord?
                    var perRecordError: Error?
                    fetchOperation.perRecordResultBlock = { _, result in
                        switch result {
                        case .success(let record):
                            fetchedRecord = record
                        case .failure(let error):
                            perRecordError = error
                        }
                    }

                    fetchOperation.fetchRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            if let perRecordError {
                                continuationState.resume(with: .failure(perRecordError))
                                return
                            }
                            guard let fetchedRecord else {
                                continuationState.resume(with: .failure(CKError(.unknownItem)))
                                return
                            }
                            continuationState.resume(with: .success(fetchedRecord))
                        case .failure(let error):
                            continuationState.resume(with: .failure(error))
                        }
                    }

                    if Task.isCancelled {
                        fetchOperation.cancel()
                        continuationState.resume(with: .failure(CancellationError()))
                        return
                    }

                    self.add(fetchOperation)
                }
            },
            onCancel: {
                fetchOperation.cancel()
                continuationState.resume(with: .failure(CancellationError()))
            })
    }
}
