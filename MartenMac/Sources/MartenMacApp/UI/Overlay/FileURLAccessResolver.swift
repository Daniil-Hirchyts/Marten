import Foundation
import MartenCore
import CoreData

enum FileURLAccessResolver {
    static func resolvedFileURL(from item: ClipItem) -> URL? {
        if item.itemTypeValue == .file,
           let reference = ManagedFileAccess.previewReference(for: item) {
            if reference.source == .legacyFileURL {
                SecurityScopedFileAccessRegistry.shared.startAccessIfNeeded(for: reference.url)
            }

            return reference.url
        }

        guard let representations = item.representations else { return nil }
        return resolvedFileURL(from: representations)
    }

    static func resolvedFileURL(from representations: Set<ClipRepresentation>) -> URL? {
        let sorted = representations.sorted { $0.displayOrder < $1.displayOrder }
        guard let fileRepresentation = sorted.first(where: { $0.kindValue == .fileURL }) else {
            return nil
        }
        return resolvedFileURL(from: fileRepresentation)
    }

    static func resolvedFileURL(from representation: ClipRepresentation) -> URL? {
        if let bookmarkedURL = ManagedFileAccess.legacyFileURL(for: representation) {
            SecurityScopedFileAccessRegistry.shared.startAccessIfNeeded(for: bookmarkedURL)
            return bookmarkedURL
        }
        return nil
    }

    private static func persistBookmarkDataIfNeeded(
        _ bookmarkData: Data,
        for representation: ClipRepresentation
    ) {
        guard let context = representation.managedObjectContext else { return }

        context.perform {
            guard representation.binaryData == nil else { return }
            representation.binaryData = bookmarkData
            try? context.save()
        }
    }
}

private final class SecurityScopedFileAccessRegistry: @unchecked Sendable {
    static let shared = SecurityScopedFileAccessRegistry()

    private let lock = NSLock()
    private var activePaths: Set<String> = []

    private init() {}

    func startAccessIfNeeded(for fileURL: URL) {
        let path = fileURL.path

        lock.lock()
        if activePaths.contains(path) {
            lock.unlock()
            return
        }
        lock.unlock()

        let didStart = fileURL.startAccessingSecurityScopedResource()
        guard didStart else { return }

        lock.lock()
        activePaths.insert(path)
        lock.unlock()
    }
}
