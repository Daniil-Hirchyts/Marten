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
            }

            filterSection(title: "Date", icon: "calendar") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(SearchDateFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            icon: dateIcon(for: filter),
                            isSelected: dateFilter == filter
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
                            isSelected: typeFilters.contains(type)
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
                                    isSelected: appFilters.contains(option.id)
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
        case .mixed:
            return "square.stack.3d.up"
        }
    }
}

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? Color.black.opacity(0.9) : Color.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AppFilterChip: View {
    let option: AppFilterOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AppIconView(bundleID: option.bundleID, size: 16)
                Text(option.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
