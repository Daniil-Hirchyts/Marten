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
        let maxPinboards = maxPinboards(for: context.family)
        let selectedPinboards = sanitizeSelectedPinboards(configuration.pinboards)
        return QuickAccessEntry(
            date: Date(),
            pinboards: mapPinboards(Array(selectedPinboards.prefix(maxPinboards)))
        )
    }

    func timeline(
        for configuration: SelectPinboardsIntent,
        in context: Context
    ) async -> Timeline<QuickAccessEntry> {
        let maxPinboards = maxPinboards(for: context.family)
        let selectedPinboards = sanitizeSelectedPinboards(configuration.pinboards)
        let entry = QuickAccessEntry(
            date: Date(),
            pinboards: mapPinboards(Array(selectedPinboards.prefix(maxPinboards)))
        )
        return Timeline(entries: [entry], policy: .after(WidgetSupport.defaultReloadDate()))
    }

    private func sanitizeSelectedPinboards(_ pinboards: [PinboardAppEntity]?) -> [PinboardAppEntity]
    {
        let selected = pinboards ?? []
        let nonNone = selected.filter { $0.id != PinboardAppEntity.noneID }
        return nonNone
    }

    private func maxPinboards(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        default:
            return 4
        }
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
        .contentMarginsDisabled()
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

    // MARK: Small

    private var smallLayout: some View {
        let pinboards = Array(entry.pinboards.prefix(1))

        return Group {
            if pinboards.isEmpty {
                // 3 controls only — top row 2, bottom row 1 full width
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        controlCell(
                            title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                        cellBorderV
                        controlCell(
                            title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
                    }
                    cellBorderH
                    controlCell(title: "New", systemImage: "plus.square", url: "marten://create")
                }
            } else {
                // 2×2: 3 controls + 1 pinboard
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        controlCell(
                            title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                        cellBorderV
                        controlCell(
                            title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
                    }
                    cellBorderH
                    HStack(spacing: 0) {
                        controlCell(
                            title: "New", systemImage: "plus.square", url: "marten://create")
                        cellBorderV
                        pinboardCell(pinboards[0])
                    }
                }
            }
        }
    }

    // MARK: Medium

    private var mediumLayout: some View {
        let pinboards = Array(entry.pinboards.prefix(2))

        return GeometryReader { geometry in
            let controlsWidth = pinboards.isEmpty ? geometry.size.width : geometry.size.width * 0.42

            HStack(spacing: 0) {
                // Controls column — always 3 stacked
                VStack(spacing: 0) {
                    controlCell(
                        title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                    cellBorderH
                    controlCell(
                        title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
                    cellBorderH
                    controlCell(title: "New", systemImage: "plus.square", url: "marten://create")
                }
                .frame(width: controlsWidth)

                if !pinboards.isEmpty {
                    cellBorderV

                    // Pinboards column — adapt to count
                    VStack(spacing: 0) {
                        pinboardCell(pinboards[0])
                        if pinboards.count > 1 {
                            cellBorderH
                            pinboardCell(pinboards[1])
                        }
                    }
                    .frame(width: geometry.size.width - controlsWidth - 0.5)
                }
            }
        }
    }

    // MARK: Large

    private var largeLayout: some View {
        let pinboards = Array(entry.pinboards.prefix(4))

        return GeometryReader { geometry in
            let controlsHeight =
                pinboards.isEmpty ? geometry.size.height : geometry.size.height * 0.30

            VStack(spacing: 0) {
                // Controls row
                HStack(spacing: 0) {
                    controlCell(
                        title: "Search", systemImage: "magnifyingglass", url: "marten://search")
                    cellBorderV
                    controlCell(
                        title: "Paste", systemImage: "doc.on.clipboard", url: "marten://paste")
                    cellBorderV
                    controlCell(title: "New", systemImage: "plus.square", url: "marten://create")
                }
                .frame(height: controlsHeight)

                if !pinboards.isEmpty {
                    cellBorderH

                    // Pinboards — adapt grid to count
                    Group {
                        switch pinboards.count {
                        case 1:
                            pinboardCell(pinboards[0])
                        case 2:
                            HStack(spacing: 0) {
                                pinboardCell(pinboards[0])
                                cellBorderV
                                pinboardCell(pinboards[1])
                            }
                        case 3:
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    pinboardCell(pinboards[0])
                                    cellBorderV
                                    pinboardCell(pinboards[1])
                                }
                                cellBorderH
                                pinboardCell(pinboards[2])
                            }
                        default:
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    pinboardCell(pinboards[0])
                                    cellBorderV
                                    pinboardCell(pinboards[1])
                                }
                                cellBorderH
                                HStack(spacing: 0) {
                                    pinboardCell(pinboards[2])
                                    cellBorderV
                                    pinboardCell(pinboards[3])
                                }
                            }
                        }
                    }
                    .frame(height: geometry.size.height - controlsHeight - 0.5)
                }
            }
        }
    }

    // MARK: Borders

    private var cellBorderH: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 0.5)
    }

    private var cellBorderV: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5)
    }

    // MARK: Cells

    private func controlCell(title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pinboardCell(_ pinboard: PinboardDisplayItem) -> some View {
        Link(destination: pinboard.deepLinkURL) {
            VStack(spacing: 3) {
                Image(systemName: pinboard.iconName ?? "pin.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: pinboard.colorHex))
                Text(pinboard.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    fileprivate init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r: Double
        let g: Double
        let b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.5
            g = 0.5
            b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
