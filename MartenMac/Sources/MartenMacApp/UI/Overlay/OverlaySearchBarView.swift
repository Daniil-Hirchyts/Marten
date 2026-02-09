import MartenCore
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

    // Total width must include search toggle, separator, and filter button.
    private var totalCollapsedWidth: CGFloat {
        searchCollapsedWidth + headerButtonSize + 1 // + separator width
    }
    
    private var totalExpandedWidth: CGFloat {
        // Expanded state includes: search toggle + text field + separator + filter button.
        searchCollapsedWidth + searchExpandedWidth + headerButtonSize + 1
    }

    private var searchFieldHorizontalPadding: CGFloat {
        isSearchExpanded ? 6 : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Search Toggle / Icon
            Button(action: onSearchButtonTap) {
                ZStack {
                    Color.clear
                        .frame(width: headerButtonSize, height: headerButtonSize)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: headerButtonIconSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("overlay.search.toggle")
            .accessibilityLabel(searchButtonAccessibilityLabel)
            .accessibilityHint(searchButtonAccessibilityHint)

            // Keep search field mounted to avoid insertion/removal work during width animation.
            HStack(spacing: 6) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .focused(searchFocused)
                    .frame(height: headerButtonSize)
                    .disabled(!isSearchExpanded)
                    .accessibilityIdentifier("overlay.search.field")
                    .accessibilityLabel("Search")
                    .accessibilityHint("Type to filter items")

                if isSearchExpanded && !searchText.isEmpty {
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
                    .disabled(!isSearchExpanded)
                    .accessibilityIdentifier("overlay.search.clear")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, searchFieldHorizontalPadding)
            .frame(
                width: isSearchExpanded ? searchExpandedWidth : 0,
                height: headerButtonSize,
                alignment: .leading
            )
            .opacity(isSearchExpanded ? 1 : 0)
            .clipped()

            // Separator
            Rectangle()
                .fill(Color.white.opacity(DesignTokens.Opacity.borderSubtle))
                .frame(width: 1, height: 16)

            // Filter Button
            Button {
                isFilterPopoverPresented.toggle()
            } label: {
                ZStack {
                    Color.clear
                        .frame(width: headerButtonSize, height: headerButtonSize)

                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: headerButtonIconSize, weight: .semibold))
                        .foregroundStyle(hasActiveFilters ? .primary : .secondary)

                    if hasActiveFilters {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
                FilterPopoverView(
                    dateFilter: $dateFilter,
                    typeFilters: $typeFilters,
                    appFilters: $appFilters,
                    appOptions: appOptions,
                    onClear: onClearFilters
                )
            }
            .accessibilityIdentifier("overlay.search.filters.toggle")
            .accessibilityLabel("Search filters")
        }
        .background {
            if #available(macOS 26.0, *) {
                Capsule()
                    .fill(Color.clear)
                    .glassNavigationStyle()
            } else {
                Capsule()
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
            }
        }
        .overlay {
            if #available(macOS 26.0, *) {
                EmptyView()
            } else {
                Capsule()
                    .stroke(
                        Color.white.opacity(DesignTokens.Opacity.borderSubtle),
                        lineWidth: 1
                    )
            }
        }
        // Animate width changes for the entire container
        .frame(
            width: isSearchExpanded ? totalExpandedWidth : totalCollapsedWidth,
            height: headerButtonSize,
            alignment: .leading
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchFieldFrameKey.self,
                    value: proxy.frame(in: .named(overlayCoordinateSpaceName))
                )
            }
        }
    }

    private var searchButtonAccessibilityLabel: String {
        "Search"
    }

    private var searchButtonAccessibilityHint: String {
        isSearchExpanded ? "Collapse search field" : "Expand search field"
    }
}
