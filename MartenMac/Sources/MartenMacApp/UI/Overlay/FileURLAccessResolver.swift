import Foundation
import MartenCore
import CoreData

enum FileURLAccessResolver {
    static func resolvedFileURL(from item: ClipItem) -> URL? {
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
        if let bookmarkData = representation.binaryData,
            let bookmarkedURL = resolveBookmarkedFileURL(from: bookmarkData)
        {
            SecurityScopedFileAccessRegistry.shared.startAccessIfNeeded(for: bookmarkedURL)
            return bookmarkedURL
        }

        guard let textData = representation.textData,
            let raw = String(data: textData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }

        let fallbackURL: URL
        if let parsed = URL(string: raw), parsed.isFileURL {
            fallbackURL = parsed
        } else {
            fallbackURL = URL(fileURLWithPath: raw)
        }

        if representation.binaryData == nil,
            let bookmarkData = try? fallbackURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        {
            persistBookmarkDataIfNeeded(bookmarkData, for: representation)
        }

        SecurityScopedFileAccessRegistry.shared.startAccessIfNeeded(for: fallbackURL)
        return fallbackURL
    }

    private static func resolveBookmarkedFileURL(from data: Data) -> URL? {
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
        }

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.isFileURL {
            return url
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
