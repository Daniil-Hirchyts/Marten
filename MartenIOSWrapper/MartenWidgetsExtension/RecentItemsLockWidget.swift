import MartenIOSApp
import SwiftUI
import WidgetKit

struct RecentItemsLockEntry: TimelineEntry {
    let date: Date
    let item: WidgetClipEntry?
}

struct RecentItemsLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentItemsLockEntry {
        RecentItemsLockEntry(
            date: Date(),
            item: WidgetSupport.placeholderEntries().first
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentItemsLockEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentItemsLockEntry>) -> Void) {
        Task {
            let service = WidgetTimelineService(
                persistenceController: WidgetSupport.makePersistenceController()
            )
            let item = try? await service.recentEntries(limit: 1).first
            let entry = RecentItemsLockEntry(date: Date(), item: item)
            completion(Timeline(entries: [entry], policy: .after(WidgetSupport.defaultReloadDate())))
        }
    }
}

struct RecentItemsLockWidget: Widget {
    let kind = "RecentItemsLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentItemsLockProvider()) { entry in
            if let item = entry.item {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marten")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(2)
                }
                .widgetURL(item.deepLinkURL)
            } else {
                Text("Marten")
                    .font(.caption)
            }
        }
        .configurationDisplayName("Recent Marten Item")
        .description("Quick lock screen access to your latest item.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
