import MartenCore
import SwiftUI

struct DashboardBottomBarView: View {
    let selectedPinboard: Pinboard?
    let actionButtonSize: CGFloat
    @Binding var isSearchExpanded: Bool
    @Binding var searchFocusRequest: Bool
    let searchQuery: Binding<String>
    let hasActiveFilters: Bool
    let onOpenPinboardPicker: () -> Void
    let onShowFilters: () -> Void
    let onShowQuickAdd: () -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let interItemSpacing: CGFloat = 10
            let dividerWidth: CGFloat = 1
            let collapsedSearchGroupWidth = (actionButtonSize * 2) + dividerWidth
            let trailingButtonWidth = actionButtonSize
            let pinboardSlotWidth = actionButtonSize
            let leadingClusterWidth = max(
                0,
                proxy.size.width - trailingButtonWidth - interItemSpacing
            )
            let expandedSearchGroupWidth = max(
                collapsedSearchGroupWidth,
                leadingClusterWidth
            )
            let expandedTextFieldWidth = max(
                0,
                expandedSearchGroupWidth - collapsedSearchGroupWidth
            )
            let textFieldWidth = isSearchExpanded ? expandedTextFieldWidth : 0

            HStack(spacing: interItemSpacing) {
                HStack(spacing: isSearchExpanded ? 0 : interItemSpacing) {
                    Button(action: onOpenPinboardPicker) {
                        Group {
                            if let pinboard = selectedPinboard {
                                PinboardIndicator(
                                    colorHex: pinboard.colorHex,
                                    sign: pinboard.iconName,
                                    size: 22
                                )
                            } else {
                                Image(systemName: "tray")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCircleBackground(isHighlighted: false)
                    .frame(width: isSearchExpanded ? 0 : pinboardSlotWidth, height: actionButtonSize)
                    .scaleEffect(isSearchExpanded ? 0.96 : 1)
                    .opacity(isSearchExpanded ? 0 : 1)
                    .allowsHitTesting(!isSearchExpanded)
                    .accessibilityHidden(isSearchExpanded)
                    .accessibilityLabel("Select Pinboard")
                    .accessibilityIdentifier("ios.dashboard.pinboardDropdown")

                    if !isSearchExpanded {
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 0) {
                        searchToggleButton

                        HStack(spacing: 6) {
                            #if os(iOS)
                            DashboardSearchTextField(
                                text: searchQuery,
                                placeholder: "Search cards\u{2026}",
                                focusRequest: $searchFocusRequest
                            )
                            .frame(height: 36)
                            #else
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField("Search cards\u{2026}", text: searchQuery)
                            #endif

                            if !searchQuery.wrappedValue.isEmpty {
                                Button {
                                    searchQuery.wrappedValue = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        .animation(MartenAnimation.quick, value: searchQuery.wrappedValue.isEmpty)
                        .padding(.horizontal, isSearchExpanded ? 10 : 0)
                        .frame(width: textFieldWidth, height: actionButtonSize, alignment: .leading)
                        .opacity(isSearchExpanded ? 1 : 0)
                        .clipped()
                        .allowsHitTesting(isSearchExpanded)

                        Button(action: onShowFilters) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(hasActiveFilters ? Color.accentColor : .primary)
                                .frame(width: actionButtonSize, height: actionButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filters")
                        .accessibilityIdentifier("ios.dashboard.filters")
                    }
                    .frame(width: isSearchExpanded ? expandedSearchGroupWidth : collapsedSearchGroupWidth)
                    .glassChipBackground(isHighlighted: false)
                }
                .frame(width: leadingClusterWidth, alignment: .leading)

                Button {
                    if isSearchExpanded {
                        onCloseSearch()
                    } else {
                        onShowQuickAdd()
                    }
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "plus")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassCircleBackground(isHighlighted: false)
                .accessibilityLabel(isSearchExpanded ? "Close Search" : "Quick Add")
                .accessibilityIdentifier(
                    isSearchExpanded ? "ios.dashboard.closeSearch" : "ios.dashboard.quickAdd"
                )
            }
            .frame(width: proxy.size.width, height: actionButtonSize, alignment: .leading)
        }
        .frame(height: actionButtonSize)
    }

    private var searchToggleButton: some View {
        Button {
            guard !isSearchExpanded else {
                searchFocusRequest = true
                return
            }
            withAnimation(MartenAnimation.smooth) {
                isSearchExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                searchFocusRequest = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: actionButtonSize, height: actionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("ios.dashboard.search")
    }
}

