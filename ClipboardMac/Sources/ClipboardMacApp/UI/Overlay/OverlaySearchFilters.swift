import AppKit
import ClipboardCore
import SwiftUI

enum SearchDateFilter: String, CaseIterable, Identifiable {
    case any
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any:
            return "Any time"
        case .today:
            return "Today"
        case .last7Days:
            return "Last 7 days"
        case .last30Days:
            return "Last 30 days"
        }
    }
}

struct AppFilterOption: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
}

struct FilterPopoverView: View {
    @Binding var dateFilter: SearchDateFilter
    @Binding var typeFilters: Set<ItemType>
    @Binding var appFilters: Set<String>
    let appOptions: [AppFilterOption]
    let onClear: () -> Void

    private let popoverWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Filters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Clear all") {
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasActiveFilters ? .secondary : .tertiary)
                .disabled(!hasActiveFilters)
                .accessibilityIdentifier("overlay.search.filters.clear")
                .accessibilityLabel("Clear filters")
                .accessibilityValue(hasActiveFilters ? "Filters active" : "No filters")
                .accessibilityHint("Clears all active filters")
            }

            filterSection(title: "Date", icon: "calendar") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(SearchDateFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            icon: dateIcon(for: filter),
                            isSelected: dateFilter == filter,
                            identifier: "overlay.search.filter.date.\(filter.rawValue)"
                        ) {
                            dateFilter = filter
                        }
                    }
                }
            }

            filterSection(title: "Type", icon: "square.3.layers.3d") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(ItemType.allCases, id: \.self) { type in
                        FilterChip(
                            title: itemTypeLabel(type),
                            icon: itemTypeIcon(type),
                            isSelected: typeFilters.contains(type),
                            identifier: "overlay.search.filter.type.\(itemTypeIdentifier(type))"
                        ) {
                            toggleType(type)
                        }
                    }
                }
            }

            filterSection(title: "App", icon: "app.dashed") {
                if appOptions.isEmpty {
                    Text("No apps found")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8
                        ) {
                            ForEach(appOptions) { option in
                                AppFilterChip(
                                    option: option,
                                    isSelected: appFilters.contains(option.id),
                                    identifier: "overlay.search.filter.app.\(appIdentifier(option))"
                                ) {
                                    toggleApp(option.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
        .padding(16)
        .frame(width: popoverWidth)
        .accessibilityIdentifier("overlay.search.filters")
    }

    private var hasActiveFilters: Bool {
        dateFilter != .any || !typeFilters.isEmpty || !appFilters.isEmpty
    }

    private func toggleType(_ type: ItemType) {
        if typeFilters.contains(type) {
            typeFilters.remove(type)
        } else {
            typeFilters.insert(type)
        }
    }

    private func toggleApp(_ id: String) {
        if appFilters.contains(id) {
            appFilters.remove(id)
        } else {
            appFilters.insert(id)
        }
    }

    private func itemTypeLabel(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "URL"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .mixed:
            return "Mixed"
        }
    }

    private func filterSection<Content: View>(
        title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func dateIcon(for filter: SearchDateFilter) -> String {
        switch filter {
        case .any:
            return "clock"
        case .today:
            return "sun.max"
        case .last7Days:
            return "7.circle"
        case .last30Days:
            return "calendar"
        }
    }

    private func itemTypeIcon(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "text.alignleft"
        case .richText:
            return "textformat"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        case .code:
            return "chevron.left.slash.chevron.right"
        case .color:
            return "paintpalette"
        case .mixed:
            return "square.stack.3d.up"
        }
    }

    private func itemTypeIdentifier(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "text"
        case .richText:
            return "richText"
        case .image:
            return "image"
        case .file:
            return "file"
        case .url:
            return "url"
        case .code:
            return "code"
        case .color:
            return "color"
        case .mixed:
            return "mixed"
        }
    }

    private func appIdentifier(_ option: AppFilterOption) -> String {
        let base = option.bundleID ?? option.id
        return base.replacingOccurrences(of: " ", with: "_")
    }
}

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Group {
                    if #available(macOS 26.0, *) {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(selectedBackgroundColor)
                        } else {
                            Capsule(style: .continuous)
                                .fill(Color.clear)
                                .glassNavigationStyle()
                        }
                    } else {
                        Capsule(style: .continuous)
                            .fill(isSelected ? selectedBackgroundColor : unselectedBackgroundColor)
                    }
                }
            )
            .overlay(
                Group {
                    if #available(macOS 26.0, *) {
                        if isSelected {
                            Capsule(style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1)
                        } else {
                            EmptyView()
                        }
                    } else {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(
                                    isSelected
                                        ? DesignTokens.Opacity.borderMedium
                                        : DesignTokens.Opacity.borderSubtle), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles filter")
    }

    private var iconColor: Color {
        if isSelected {
            return colorScheme == .dark ? .black.opacity(0.9) : .white.opacity(0.9)
        } else {
            return colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
        }
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? .white : .black
        }
    }

    private var selectedBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color.black.opacity(0.85)
    }

    private var unselectedBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(DesignTokens.Opacity.backgroundMedium)
            : Color.black.opacity(0.1)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(DesignTokens.Opacity.borderMedium)
            : Color.black.opacity(0.2)
    }
}

private struct AppFilterChip: View {
    let option: AppFilterOption
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AppIconView(bundleID: option.bundleID, size: 16)
                Text(option.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if #available(macOS 26.0, *) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    (colorScheme == .dark ? Color.white : Color.black).opacity(0.9))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.clear)
                                .glassStyle(shape: .roundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isSelected
                                    ? (colorScheme == .dark ? Color.white : Color.black).opacity(
                                        0.9)
                                    : (colorScheme == .dark ? Color.white : Color.black).opacity(
                                        DesignTokens.Opacity.backgroundMedium))
                    }
                }
            )
            .overlay(
                Group {
                    if #available(macOS 26.0, *) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    (colorScheme == .dark ? Color.white : Color.black).opacity(
                                        DesignTokens.Opacity.borderMedium), lineWidth: 1)
                        } else {
                            EmptyView()
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                (colorScheme == .dark ? Color.white : Color.black).opacity(
                                    isSelected
                                        ? DesignTokens.Opacity.borderMedium
                                        : DesignTokens.Opacity.borderSubtle), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(option.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles app filter")
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? .white : .black
        }
    }
}
