import AppKit
import SwiftUI

extension OverlayShellView {
    func handleSearchButtonTap() {
        if isSearchExpanded {
            if !isFilterPopoverPresented {
                searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
            }
            isFilterPopoverPresented.toggle()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSearchExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    func handleSearchClear() {
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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

