import ClipboardCore
import SwiftUI

struct OverlaySearchBarView: View {
    @Binding var isSearchExpanded: Bool
    @Binding var isFilterPopoverPresented: Bool
    @Binding var searchText: String
    let searchFocused: FocusState<Bool>.Binding

    @Binding var dateFilter: SearchDateFilter
    @Binding var typeFilters: Set<ItemType>
    @Binding var appFilters: Set<String>
    let appOptions: [AppFilterOption]
    let hasActiveFilters: Bool

    let headerButtonSize: CGFloat
    let headerButtonIconSize: CGFloat
    let searchCollapsedWidth: CGFloat
    let searchExpandedWidth: CGFloat
    let overlayCoordinateSpaceName: String

    let onSearchButtonTap: () -> Void
    let onSearchClear: () -> Void
    let onClearFilters: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Button(action: onSearchButtonTap) {
                    searchIcon
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityIdentifier("overlay.search.toggle")
                .accessibilityLabel(searchButtonAccessibilityLabel)
                .accessibilityValue(searchButtonAccessibilityValue)
                .accessibilityHint(searchButtonAccessibilityHint)

                if isSearchExpanded {
                    HStack(spacing: 6) {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .focused(searchFocused)
                            .frame(height: headerButtonSize)
                            .accessibilityIdentifier("overlay.search.field")
                            .accessibilityLabel("Search")
                            .accessibilityValue(searchFieldAccessibilityValue)
                            .accessibilityHint("Type to filter items")

                        Button(action: onSearchClear) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(3)
                                .background(
                                    Color.white.opacity(DesignTokens.Opacity.backgroundMedium)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .accessibilityIdentifier("overlay.search.clear")
                        .accessibilityLabel("Clear search")
                        .accessibilityHint("Clears search text and collapses search field")
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 6)
                }
            }
            .background {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                        .opacity(isSearchExpanded ? 1 : 0)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                        .opacity(isSearchExpanded ? 1 : 0)
                }
            }
            .overlay {
                if #available(macOS 26.0, *) {
                    EmptyView()
                } else {
                    Capsule()
                        .stroke(
                            Color.white.opacity(
                                isSearchExpanded ? DesignTokens.Opacity.borderStrong : 0),
                            lineWidth: 1
                        )
                }
            }
            .frame(
                width: isSearchExpanded ? searchExpandedWidth : searchCollapsedWidth,
                height: headerButtonSize,
                alignment: .leading
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchExpanded)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SearchFieldFrameKey.self,
                        value: proxy.frame(in: .named(overlayCoordinateSpaceName))
                    )
                }
            }
            .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
                FilterPopoverView(
                    dateFilter: $dateFilter,
                    typeFilters: $typeFilters,
                    appFilters: $appFilters,
                    appOptions: appOptions,
                    onClear: onClearFilters
                )
            }
        }
    }

    private var searchButtonAccessibilityLabel: String {
        isSearchExpanded ? "Search filters" : "Search"
    }

    private var searchButtonAccessibilityValue: String {
        var parts: [String] = []
        parts.append(isSearchExpanded ? "Expanded" : "Collapsed")
        if hasActiveFilters {
            parts.append("Filters active")
        }
        return parts.joined(separator: ", ")
    }

    private var searchButtonAccessibilityHint: String {
        if isSearchExpanded {
            return isFilterPopoverPresented ? "Hide search filters" : "Show search filters"
        }
        return "Expand search field"
    }

    private var searchFieldAccessibilityValue: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty" : trimmed
    }

    private var searchIcon: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .frame(width: headerButtonSize, height: headerButtonSize)
                    .glassCircleButton()
                    .opacity(isSearchExpanded ? 0 : 1)
            } else {
                Circle()
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                    .frame(width: headerButtonSize, height: headerButtonSize)
                    .opacity(isSearchExpanded ? 0 : 1)
            }

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            if hasActiveFilters {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .offset(x: 9, y: -9)
            }
        }
        .frame(width: headerButtonSize, height: headerButtonSize)
        .contentShape(Rectangle())
    }
}
