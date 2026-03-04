import Foundation

public enum ManagedFileAccessError: Error, Equatable {
    case missingManagedFile
    case missingSourceData
    case failedToCreateExportDirectory
}

public struct ManagedFileReference: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case asset
        case legacyFileURL
        case stagedBinaryData
    }

    public let url: URL
    public let source: Source
    public let fileExtension: String?

    public init(url: URL, source: Source, fileExtension: String?) {
        self.url = url
        self.source = source
        self.fileExtension = fileExtension
    }
}

public enum ManagedFileAccess {
    public static func previewReference(
        for item: ClipItem,
        assetStore: AssetStore = .shared,
        fileManager: FileManager = .default
    ) -> ManagedFileReference? {
        guard item.itemTypeValue == .file else { return nil }
        let representations = sortedRepresentations(for: item)

        for representation in representations where representation.kindValue == .custom {
            if let assetRef = representation.assetRef,
               let fileURL = assetStore.existingURLForAsset(
                   assetRef,
                   fileExtension: representation.fileExtension
               ) {
                return ManagedFileReference(
                    url: fileURL,
                    source: .asset,
                    fileExtension: normalizedRepresentationFileExtension(representation)
                )
            }

            if let data = representation.binaryData,
               let stagedURL = try? stageBinaryData(
                   data,
                   for: item,
                   fileExtension: normalizedRepresentationFileExtension(representation),
                   fileManager: fileManager
               ) {
                return ManagedFileReference(
                    url: stagedURL,
                    source: .stagedBinaryData,
                    fileExtension: normalizedRepresentationFileExtension(representation)
                )
            }
        }

        if let legacyURL = legacyFileURL(for: item) {
            return ManagedFileReference(
                url: legacyURL,
                source: .legacyFileURL,
                fileExtension: normalizedRepresentationFileExtension(
                    sortedRepresentations(for: item).first(where: { $0.kindValue == .fileURL })
                )
            )
        }

        return nil
    }

    public static func previewURL(
        for item: ClipItem,
        assetStore: AssetStore = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        previewReference(for: item, assetStore: assetStore, fileManager: fileManager)?.url
    }

    public static func exportURL(
        for item: ClipItem,
        assetStore: AssetStore = .shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let reference = previewReference(
            for: item,
            assetStore: assetStore,
            fileManager: fileManager
        ) else {
            throw ManagedFileAccessError.missingManagedFile
        }

        let fileName = exportFileName(for: item, fallbackExtension: reference.fileExtension)
        let destination = try exportDirectoryURL(for: item, fileManager: fileManager)
            .appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        switch reference.source {
        case .asset, .stagedBinaryData:
            do {
                try fileManager.copyItem(at: reference.url, to: destination)
            } catch {
                if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: destination)
                }
                let data = try Data(contentsOf: reference.url)
                try data.write(to: destination, options: [.atomic])
            }

        case .legacyFileURL:
            let didStart = reference.url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    reference.url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try fileManager.copyItem(at: reference.url, to: destination)
            } catch {
                if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: destination)
                }
                let data = try Data(contentsOf: reference.url)
                try data.write(to: destination, options: [.atomic])
            }
        }

        return destination
    }

    public static func displayName(for item: ClipItem) -> String? {
        if let customTitle = normalizedUserFacingFileName(item.customTitle) {
            return customTitle
        }

        if let primaryName = normalizedStoredFileName(item.primaryText) {
            return primaryName
        }

        return legacyFileURL(for: item)?.lastPathComponent
    }

    public static func exportFileName(for item: ClipItem, fallbackExtension: String?) -> String {
        let baseName =
            normalizedStoredFileName(item.primaryText)
            ?? legacyFileURL(for: item)?.lastPathComponent
            ?? "File"

        guard let fallbackExtension = ManagedFileImportService.normalizedFileExtension(fallbackExtension) else {
            return sanitizeFileName(baseName)
        }

        let sanitized = sanitizeFileName(baseName)
        if (sanitized as NSString).pathExtension.isEmpty {
            return (sanitized as NSString).appendingPathExtension(fallbackExtension) ?? sanitized
        }
        return sanitized
    }

    public static func legacyFileURL(for item: ClipItem) -> URL? {
        let representations = sortedRepresentations(for: item)
        guard let fileRepresentation = representations.first(where: { $0.kindValue == .fileURL }) else {
            return nil
        }
        return legacyFileURL(for: fileRepresentation)
    }

    public static func legacyFileURL(for representation: ClipRepresentation) -> URL? {
        if let bookmarkData = representation.binaryData,
           let bookmarkedURL = resolveBookmarkedFileURL(from: bookmarkData) {
            return bookmarkedURL
        }

        guard
            let textData = representation.textData,
            let raw = String(data: textData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }

        if let parsed = URL(string: raw), parsed.isFileURL {
            return parsed
        }

        return URL(fileURLWithPath: raw)
    }

    static func normalizedStoredFileName(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue).lastPathComponent
        }

        if rawValue.hasPrefix("file://"), let fileURL = URL(string: rawValue) {
            return fileURL.lastPathComponent
        }

        return rawValue
    }

    private static func exportDirectoryURL(
        for item: ClipItem,
        fileManager: FileManager
    ) throws -> URL {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let version = Int64(item.modifiedAt.timeIntervalSince1970 * 1000)
        let directory = baseURL
            .appendingPathComponent("Marten", isDirectory: true)
            .appendingPathComponent("ManagedFileExports", isDirectory: true)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent("\(version)", isDirectory: true)

        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
        } catch {
            throw ManagedFileAccessError.failedToCreateExportDirectory
        }

        return directory
    }

    private static func stageBinaryData(
        _ data: Data,
        for item: ClipItem,
        fileExtension: String?,
        fileManager: FileManager
    ) throws -> URL {
        let fileName = exportFileName(for: item, fallbackExtension: fileExtension)
        let destination = try exportDirectoryURL(for: item, fileManager: fileManager)
            .appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: [.atomic])
        }

        return destination
    }

    private static func normalizedRepresentationFileExtension(_ representation: ClipRepresentation?) -> String? {
        ManagedFileImportService.normalizedFileExtension(representation?.fileExtension)
    }

    private static func sortedRepresentations(for item: ClipItem) -> [ClipRepresentation] {
        (item.representations ?? []).sorted { $0.displayOrder < $1.displayOrder }
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(
            of: "/",
            with: "-"
        ).replacingOccurrences(of: ":", with: "-")

        return sanitized.isEmpty ? "File" : sanitized
    }

    private static func normalizedUserFacingFileName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return sanitizeFileName(value)
    }

    private static func resolveBookmarkedFileURL(from data: Data) -> URL? {
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
        }

        #if os(macOS)
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
        }
        #endif

        return nil
    }
}
