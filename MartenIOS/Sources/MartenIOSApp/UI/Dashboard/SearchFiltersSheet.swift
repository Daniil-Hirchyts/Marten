import MartenCore
import SwiftUI

struct SearchFiltersSheet: View {
    @Bindable var searchModel: DashboardSearchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filterSection(title: "Date", icon: "calendar") {
                        FlowLayout(spacing: 8) {
                            ForEach([ClipItemDateFilter.any, .today, .yesterday, .last7Days, .last30Days], id: \.self) { filter in
                                FilterChipButton(
                                    title: filter.label,
                                    icon: dateIcon(for: filter),
                                    badge: nil,
                                    isSelected: searchModel.dateFilter == filter,
                                    style: .capsule
                                ) {
                                    searchModel.dateFilter = filter
                                }
                            }
                        }
                    }

                    filterSection(title: "Content Type", icon: "doc.on.doc") {
                        FlowLayout(spacing: 8) {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                FilterChipButton(
                                    title: type.label,
                                    icon: itemTypeIcon(type),
                                    badge: nil,
                                    isSelected: searchModel.selectedTypes.contains(type),
                                    style: .capsule
                                ) {
                                    searchModel.toggleType(type)
                                }
                            }
                        }
                    }

                    filterSection(title: "Application", icon: "app") {
                        if searchModel.appOptions.isEmpty {
                            Text("No apps available")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(searchModel.appOptions) { option in
                                    AppFilterChipButton(
                                        option: option,
                                        isSelected: searchModel.selectedSourceApps.contains(option.id)
                                    ) {
                                        searchModel.toggleSourceApp(option.id)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                        }
                    }

                    if !searchModel.deviceOptions.isEmpty {
                        filterSection(title: "Source Device", icon: "laptopcomputer.and.iphone") {
                            FlowLayout(spacing: 8) {
                                ForEach(searchModel.deviceOptions) { device in
                                    FilterChipButton(
                                        title: device.title,
                                        icon: nil,
                                        badge: "\(device.count)",
                                        isSelected: searchModel.selectedSourceDevices.contains(device.value),
                                        style: .capsule
                                    ) {
                                        searchModel.toggleSourceDevice(device.value)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Search Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if searchModel.hasActiveFilters {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") {
                            searchModel.clearAllFilters()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.8))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .padding(.leading, 2)
            content()
        }
        .padding(.vertical, 4)
    }

    private func dateIcon(for filter: ClipItemDateFilter) -> String {
        switch filter {
        case .any: return "clock"
        case .today: return "sun.max"
        case .yesterday: return "moon"
        case .last7Days: return "7.circle"
        case .last30Days: return "calendar"
        }
    }

    private func itemTypeIcon(_ type: ItemType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .code: return "chevron.left.slash.chevron.right"
        case .color: return "paintpalette"
        case .mixed: return "square.stack.3d.up"
        }
    }
}

private enum FilterChipStyle {
    case capsule
    case roundedRect(cornerRadius: CGFloat)
}

private struct FilterChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    let style: FilterChipStyle

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
            .background(background(isPressed: configuration.isPressed))
            .overlay(border(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isSelected)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        if isSelected {
            switch style {
            case .capsule:
                Capsule().fill(Color.accentColor)
            case .roundedRect(let cornerRadius):
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor)
            }
        } else {
            switch style {
            case .capsule:
                if #available(iOS 26, macOS 26, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.04))
                }
            case .roundedRect(let cornerRadius):
                if #available(iOS 26, macOS 26, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.04))
                }
            }
        }
    }

    @ViewBuilder
    private func border(isPressed: Bool) -> some View {
        let strokeColor = isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)

        switch style {
        case .capsule:
            Capsule().strokeBorder(strokeColor, lineWidth: 0.5)
        case .roundedRect(let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 0.5)
        }
    }
}

private struct FilterChipButton: View {
    let title: String
    let icon: String?
    let badge: String?
    let isSelected: Bool
    let style: FilterChipStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.medium))
                }

                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(Color.white.opacity(0.9))
                                : AnyShapeStyle(.secondary)
                        )
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(FilterChipButtonStyle(isSelected: isSelected, style: style))
    }
}

private struct AppFilterChipButton: View {
    let option: DashboardSourceAppOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SourceAppIconBadge(bundleID: option.bundleID, appName: option.name, iconData: nil, size: 20)

                Text(option.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)

                Text("\(option.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(Color.white.opacity(0.9))
                            : AnyShapeStyle(.secondary)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(FilterChipButtonStyle(isSelected: isSelected, style: .roundedRect(cornerRadius: 14)))
    }
}

