import MartenIOSApp
import SwiftUI
import WidgetKit

struct QuickAccessEntry: TimelineEntry {
    let date: Date
    let pinboards: [PinboardDisplayItem]
}

struct PinboardDisplayItem: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let iconName: String?
    let deepLinkURL: URL
}

struct QuickAccessProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickAccessEntry {
        QuickAccessEntry(
            date: Date(),
            pinboards: [
                PinboardDisplayItem(
                    id: "placeholder",
                    name: "My Pinboard",
                    colorHex: "#5A7DFF",
                    iconName: nil,
                    deepLinkURL: URL(string: "marten://pinboard")!
                )
            ]
        )
    }

    func snapshot(
        for configuration: SelectPinboardsIntent,
        in context: Context
    ) async -> QuickAccessEntry {
        QuickAccessEntry(
            date: Date(),
            pinboards: mapPinboards(configuration.pinboards)
        )
    }

    func timeline(
        for configuration: SelectPinboardsIntent,
        in context: Context
    ) async -> Timeline<QuickAccessEntry> {
        let entry = QuickAccessEntry(
            date: Date(),
            pinboards: mapPinboards(configuration.pinboards)
        )
        return Timeline(entries: [entry], policy: .after(WidgetSupport.defaultReloadDate()))
    }

    private func mapPinboards(_ entities: [PinboardAppEntity]) -> [PinboardDisplayItem] {
        entities.map { entity in
            PinboardDisplayItem(
                id: entity.id,
                name: entity.name,
                colorHex: entity.colorHex,
                iconName: entity.iconName,
                deepLinkURL: URL(string: "marten://pinboard/\(entity.id)")!
            )
        }
    }
}

struct MartenQuickAccessWidget: Widget {
    let kind = "MartenQuickAccessWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectPinboardsIntent.self,
            provider: QuickAccessProvider()
        ) { entry in
            QuickAccessWidgetView(entry: entry)
        }
        .configurationDisplayName("Marten Quick Access")
        .description("Controls and pinboards at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - View

struct QuickAccessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickAccessEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            default:
                largeLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Small – 2×2 grid: 3 controls + 1 pinboard

    private var smallLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                controlCell(title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                controlCell(title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
            }
            HStack(spacing: 6) {
                controlCell(title: "New", systemImage: "plus", url: "marten://create")
                if let pinboard = entry.pinboards.first {
                    pinboardCell(pinboard)
                } else {
                    placeholderPinboardCell()
                }
            }
        }
        .padding(8)
    }

    // MARK: Medium – single row: 3 controls + 2 pinboards

    private var mediumLayout: some View {
        HStack(spacing: 8) {
            controlsColumn
            ForEach(entry.pinboards.prefix(2)) { pinboard in
                pinboardCell(pinboard)
            }
            if entry.pinboards.count < 2 {
                ForEach(0..<(2 - entry.pinboards.count), id: \.self) { _ in
                    placeholderPinboardCell()
                }
            }
        }
        .padding(10)
    }

    // MARK: Large – controls row on top, pinboards grid below

    private var largeLayout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                controlCell(title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                controlCell(title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
                controlCell(title: "New", systemImage: "plus", url: "marten://create")
            }
            .frame(maxHeight: 60)

            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entry.pinboards.prefix(4)) { pinboard in
                    pinboardCell(pinboard)
                }
                if entry.pinboards.count < 4 {
                    ForEach(0..<(4 - entry.pinboards.count), id: \.self) { _ in
                        placeholderPinboardCell()
                    }
                }
            }
        }
        .padding(10)
    }

    // MARK: Controls column (for medium)

    private var controlsColumn: some View {
        VStack(spacing: 6) {
            controlCell(title: "Search", systemImage: "magnifyingglass", url: "marten://search")
            controlCell(title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
            controlCell(title: "New", systemImage: "plus", url: "marten://create")
        }
        .frame(maxWidth: 80)
    }

    // MARK: Cells

    private func controlCell(title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.blue.gradient)
            )
        }
    }

    private func pinboardCell(_ pinboard: PinboardDisplayItem) -> some View {
        Link(destination: pinboard.deepLinkURL) {
            VStack(spacing: 4) {
                if let iconName = pinboard.iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(pinboard.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: pinboard.colorHex).gradient)
            )
        }
    }

    private func placeholderPinboardCell() -> some View {
        VStack(spacing: 4) {
            Image(systemName: "pin")
                .font(.system(size: 16, weight: .semibold))
            Text("Pinboard")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
        )
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
