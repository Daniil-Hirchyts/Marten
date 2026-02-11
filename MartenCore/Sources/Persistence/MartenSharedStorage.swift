import Foundation

public enum MartenSharedStorageError: Error, LocalizedError, Sendable {
    case appGroupContainerUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable(let identifier):
            return "App Group container unavailable for \(identifier)"
        }
    }
}

public struct MartenSharedStorage: Sendable {
    public struct MigrationResult: Sendable, Equatable {
        public let movedStoreFiles: Bool
        public let movedAssets: Bool

        public init(movedStoreFiles: Bool, movedAssets: Bool) {
            self.movedStoreFiles = movedStoreFiles
            self.movedAssets = movedAssets
        }
    }

    public let appGroupIdentifier: String
    private let explicitContainerURL: URL?

    public init(appGroupIdentifier: String, explicitContainerURL: URL? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
        self.explicitContainerURL = explicitContainerURL
    }

    public func appGroupContainerURL(fileManager: FileManager = .default) throws -> URL {
        if let explicitContainerURL {
            return explicitContainerURL
        }
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw MartenSharedStorageError.appGroupContainerUnavailable(appGroupIdentifier)
        }
        return url
    }

    public func sharedMartenDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let root = try appGroupContainerURL(fileManager: fileManager)
        let directory = root.appendingPathComponent("Marten", isDirectory: true)
        try ensureDirectoryExists(at: directory, fileManager: fileManager)
        return directory
    }

    public func sharedStoreURL(fileManager: FileManager = .default) throws -> URL {
        try sharedMartenDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("MartenCore.sqlite")
    }

    public func sharedAssetsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try sharedMartenDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Assets", isDirectory: true)
        try ensureDirectoryExists(at: directory, fileManager: fileManager)
        return directory
    }

    public func legacyStoreURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL
            .appendingPathComponent("Marten", isDirectory: true)
            .appendingPathComponent("MartenCore.sqlite")
    }

    public func legacyAssetsDirectoryURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL
            .appendingPathComponent("Marten", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
    }

    /// Moves legacy app-support storage into the App Group container when needed.
    /// Safe to call repeatedly.
    @discardableResult
    public func migrateLegacyDataIfNeeded(
        legacyStoreURL: URL? = nil,
        legacyAssetsURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> MigrationResult {
        let sourceStore = legacyStoreURL ?? self.legacyStoreURL(fileManager: fileManager)
        let sourceAssets = legacyAssetsURL ?? self.legacyAssetsDirectoryURL(fileManager: fileManager)
        let targetStore = try sharedStoreURL(fileManager: fileManager)
        let targetAssets = try sharedAssetsDirectoryURL(fileManager: fileManager)

        var movedStore = false
        var movedAssets = false

        if try migrateStoreFiles(
            from: sourceStore,
            to: targetStore,
            fileManager: fileManager
        ) {
            movedStore = true
        }

        if try migrateAssetsDirectory(
            from: sourceAssets,
            to: targetAssets,
            fileManager: fileManager
        ) {
            movedAssets = true
        }

        return MigrationResult(
            movedStoreFiles: movedStore,
            movedAssets: movedAssets
        )
    }

    private func migrateStoreFiles(
        from source: URL,
        to target: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let targetHasPrimaryStore = fileManager.fileExists(atPath: target.path)
        var movedAny = false

        let pairs: [(URL, URL)] = [
            (source, target),
            (URL(fileURLWithPath: "\(source.path)-wal"), URL(fileURLWithPath: "\(target.path)-wal")),
            (URL(fileURLWithPath: "\(source.path)-shm"), URL(fileURLWithPath: "\(target.path)-shm")),
        ]

        for (sourceFile, targetFile) in pairs {
            guard fileManager.fileExists(atPath: sourceFile.path) else { continue }
            if fileManager.fileExists(atPath: targetFile.path) {
                continue
            }
            // If main target store already exists, do not move legacy sidecars.
            if targetHasPrimaryStore && sourceFile.path != source.path {
                continue
            }
            try ensureDirectoryExists(
                at: targetFile.deletingLastPathComponent(),
                fileManager: fileManager
            )
            try fileManager.moveItem(at: sourceFile, to: targetFile)
            movedAny = true
        }

        return movedAny
    }

    private func migrateAssetsDirectory(
        from source: URL,
        to target: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: source.path) else { return false }
        try ensureDirectoryExists(at: target, fileManager: fileManager)

        var movedAny = false
        let sourceFiles = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )

        for sourceFile in sourceFiles {
            let destination = target.appendingPathComponent(sourceFile.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                continue
            }
            try fileManager.moveItem(at: sourceFile, to: destination)
            movedAny = true
        }

        let remaining = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        if remaining.isEmpty {
            try? fileManager.removeItem(at: source)
        }

        return movedAny
    }

    private func ensureDirectoryExists(
        at url: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            return
        }
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}
