import AppKit
import SwiftUI

extension OverlayShellView {
    func handleSearchButtonTap() {
        if isSearchExpanded {
            // Collapse search if already expanded
            withAnimation(OverlayAnimation.searchSpring) {
                isSearchExpanded = false
                searchFocused = false
            }
        } else {
            // If collapsed: Expand and Focus
            withAnimation(OverlayAnimation.searchSpring) {
                isSearchExpanded = true
            }

            DispatchQueue.main.async {
                searchFocused = true
            }
        }
    }

    func handleSearchClear() {
        isFilterPopoverPresented = false
        withAnimation(OverlayAnimation.searchSpring) {
            isSearchExpanded = false
            searchModel.searchText = ""
            searchFocused = false
        }
    }

    func closeSearchIfEmpty() {
        guard isSearchExpanded,
            searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isSearchExpanded = false
            searchFocused = false
        }
    }
}
