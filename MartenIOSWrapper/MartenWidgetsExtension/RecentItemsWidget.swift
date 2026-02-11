import MartenIOSApp
import SwiftUI
import WidgetKit

struct RecentItemsWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetClipEntry]
}

struct RecentItemsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentItemsWidgetEntry {
        RecentItemsWidgetEntry(
            date: Date(),
            items: WidgetSupport.placeholderEntries()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentItemsWidgetEntry) -> Void) {
        completion(
            RecentItemsWidgetEntry(
                date: Date(),
                items: WidgetSupport.placeholderEntries()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentItemsWidgetEntry>) -> Void) {
        Task {
            let service = WidgetTimelineService(
                persistenceController: WidgetSupport.makePersistenceController()
            )
            let items = (try? await service.recentEntries(limit: 4)) ?? WidgetSupport.placeholderEntries()
            let entry = RecentItemsWidgetEntry(date: Date(), items: items)
            completion(Timeline(entries: [entry], policy: .after(WidgetSupport.defaultReloadDate())))
        }
    }
}

struct RecentItemsWidget: Widget {
    let kind = "RecentItemsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentItemsProvider()) { entry in
            RecentItemsWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Marten Items")
        .description("Quick view of your latest clipboard items.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentItemsWidgetView: View {
    let entry: RecentItemsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.headline)

            if entry.items.isEmpty {
                Text("No items yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .widgetURL(entry.items.first?.deepLinkURL)
    }
}
