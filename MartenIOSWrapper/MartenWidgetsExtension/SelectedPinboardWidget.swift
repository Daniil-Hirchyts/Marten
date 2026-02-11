import MartenIOSApp
import SwiftUI
import WidgetKit

struct SelectedPinboardWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let items: [WidgetClipEntry]
    let pinboardID: UUID?
}

struct SelectedPinboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelectedPinboardWidgetEntry {
        SelectedPinboardWidgetEntry(
            date: Date(),
            title: "Selected Pinboard",
            items: WidgetSupport.placeholderEntries(),
            pinboardID: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SelectedPinboardWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelectedPinboardWidgetEntry>) -> Void) {
        Task {
            let persistence = WidgetSupport.makePersistenceController()
            let service = WidgetTimelineService(persistenceController: persistence)
            let queryService = SharedClipQueryService(persistenceController: persistence)

            let groupDefaults = UserDefaults(suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier)
            let selectedPinboardID = groupDefaults?
                .string(forKey: MartenIOSDefaults.selectedPinboardIDKey)
                .flatMap(UUID.init(uuidString:))

            let pinboards = (try? await queryService.pinboards()) ?? []
            let selectedPinboard = pinboards.first(where: { $0.id == selectedPinboardID })

            let items: [WidgetClipEntry]
            if let selectedPinboardID {
                items = (try? await service.entries(forPinboardID: selectedPinboardID, limit: 4))
                    ?? WidgetSupport.placeholderEntries()
            } else {
                items = (try? await service.recentEntries(limit: 4))
                    ?? WidgetSupport.placeholderEntries()
            }

            let entry = SelectedPinboardWidgetEntry(
                date: Date(),
                title: selectedPinboard?.name ?? "Selected Pinboard",
                items: items,
                pinboardID: selectedPinboardID
            )
            completion(Timeline(entries: [entry], policy: .after(WidgetSupport.defaultReloadDate())))
        }
    }
}

struct SelectedPinboardWidget: Widget {
    let kind = "SelectedPinboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SelectedPinboardProvider()) { entry in
            SelectedPinboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Selected Pinboard")
        .description("Shows recent items from your selected pinboard.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SelectedPinboardWidgetView: View {
    let entry: SelectedPinboardWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)

            if entry.items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .widgetURL(
            entry.pinboardID.map { URL(string: "marten://pinboard/\($0.uuidString)")! }
                ?? entry.items.first?.deepLinkURL
        )
    }
}
