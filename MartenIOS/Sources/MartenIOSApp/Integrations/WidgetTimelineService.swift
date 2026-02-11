import Foundation
import MartenCore

public struct WidgetClipEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let createdAt: Date
    public let deepLinkURL: URL

    public init(
        id: UUID,
        title: String,
        subtitle: String,
        createdAt: Date,
        deepLinkURL: URL
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.deepLinkURL = deepLinkURL
    }
}

public actor WidgetTimelineService {
    private let queryService: SharedClipQueryService

    public init(persistenceController: PersistenceController) {
        self.queryService = SharedClipQueryService(persistenceController: persistenceController)
    }

    public func recentEntries(limit: Int = 6) async throws -> [WidgetClipEntry] {
        let items = try await queryService.recentItems(limit: max(1, limit))
        return items.map(mapSummaryToEntry)
    }

    public func entries(
        forPinboardID pinboardID: UUID,
        limit: Int = 6
    ) async throws -> [WidgetClipEntry] {
        let items = try await queryService.recentItems(
            pinboardID: pinboardID,
            limit: max(1, limit)
        )
        return items.map(mapSummaryToEntry)
    }

    private func mapSummaryToEntry(_ summary: SharedClipItemSummary) -> WidgetClipEntry {
        let trimmedText = summary.insertionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedText.isEmpty ? "Untitled Item" : String(trimmedText.prefix(80))
        let subtitle = summary.sourceAppName ?? "Marten"
        let deepLinkURL = URL(string: "marten://item/\(summary.id.uuidString)")!

        return WidgetClipEntry(
            id: summary.id,
            title: title,
            subtitle: subtitle,
            createdAt: summary.createdAt,
            deepLinkURL: deepLinkURL
        )
    }
}
