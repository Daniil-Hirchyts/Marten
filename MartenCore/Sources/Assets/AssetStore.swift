import Foundation

public enum AssetStoreError: Error {
    case missingAsset
}

public final class AssetStore {
    // `nonisolated(unsafe)` because this is set exactly once at app startup (before any
    // concurrent reads) and then treated as immutable. On iOS the App Group path is injected
    // by MartenIOSStorageConfiguration so every component reads from the same location as the
    // writer; on macOS the default (applicationSupportDirectory) is used throughout.
    nonisolated(unsafe) public static var shared = AssetStore()

    private let baseURL: URL
    private let fileManager: FileManager

    public init(baseURL: URL = AssetStore.defaultBaseURL(), fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.fileManager = fileManager
        ensureBaseDirectory()
    }

    public func store(data: Data, fileExtension: String? = nil) throws -> UUID {
        let assetRef = UUID()
        let url = urlForAsset(assetRef, fileExtension: fileExtension)
        try data.write(to: url, options: .atomic)
        return assetRef
    }

    public func load(assetRef: UUID, fileExtension: String? = nil) throws -> Data {
        let url = urlForAsset(assetRef, fileExtension: fileExtension)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AssetStoreError.missingAsset
        }
        return try Data(contentsOf: url)
    }

    public func delete(assetRef: UUID, fileExtension: String? = nil) throws {
        let url = urlForAsset(assetRef, fileExtension: fileExtension)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            return
        }

        let uuidString = assetRef.uuidString
        let contents = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil, options: [])
        for item in contents {
            if item.deletingPathExtension().lastPathComponent == uuidString {
                try fileManager.removeItem(at: item)
                return
            }
        }

        throw AssetStoreError.missingAsset
    }

    public func urlForAsset(_ assetRef: UUID, fileExtension: String? = nil) -> URL {
        let filename = fileExtension.map { "\(assetRef.uuidString).\($0)" } ?? assetRef.uuidString
        return baseURL.appendingPathComponent(filename)
    }

    private func ensureBaseDirectory() {
        if !fileManager.fileExists(atPath: baseURL.path) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    public static func defaultBaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent("Marten", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
    }
}
