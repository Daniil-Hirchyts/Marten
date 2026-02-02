import AppKit
import ClipboardCore
import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    var filteredItems: [ClipItem] {
        let selectedPinboardID = searchModel.selectedPinboardID
        let sourceItems = searchModel.isSearchTextActive ? searchModel.searchResults : Array(items)
        let baseList = sourceItems.filter { item in
            isItemVisible(item, selectedPinboardID: selectedPinboardID)
        }
        let filtered = searchModel.applyFilters(to: baseList)
        return sortItems(filtered)
    }

    var isSearchActive: Bool {
        searchModel.isSearchActive
    }

    var visiblePinboards: [Pinboard] {
        pinboards.filter { !$0.isSystemClipboard }
    }

    var visiblePinboardIDs: [UUID] {
        visiblePinboards.map(\.id)
    }

    var movablePinboards: [Pinboard] {
        visiblePinboards.filter { pinboardLockController.canAccess(pinboardID: $0.id) }
    }

    var selectedCustomPinboard: Pinboard? {
        guard let selectedPinboardID = searchModel.selectedPinboardID else { return nil }
        return visiblePinboards.first(where: { $0.id == selectedPinboardID })
    }

    var selectedPinboardIsLocked: Bool {
        guard let selectedCustomPinboard else { return false }
        return pinboardLockController.isLocked(pinboardID: selectedCustomPinboard.id)
    }

    var selectedPinboardIsAccessible: Bool {
        guard let selectedCustomPinboard else { return true }
        return pinboardLockController.canAccess(pinboardID: selectedCustomPinboard.id)
    }

    var isSelectedPinboardAwaitingUnlock: Bool {
        searchModel.selectedPinboardID != nil && selectedPinboardIsLocked
            && !selectedPinboardIsAccessible
    }

    var allowPinning: Bool {
        searchModel.selectedPinboardID != nil && selectedPinboardIsAccessible
    }

    var isDragEnabled: Bool {
        true
    }

    var isReorderingEnabled: Bool {
        isDragEnabled
            && searchModel.selectedPinboardID != nil
            && selectedPinboardIsAccessible
            && !isSearchActive
    }

    var itemsSourceAppsHash: Int {
        items.map { $0.sourceAppBundleID ?? $0.sourceAppName ?? "" }
            .sorted()
            .joined()
            .hashValue
    }

    var pinboardSelectionKey: String {
        searchModel.selectedPinboardID?.uuidString ?? "all-pinboards"
    }

    var keyHandlerRefreshToken: String {
        let renameItem = renameItemID?.uriRepresentation().absoluteString ?? "nil"
        let renamePinboard = renamePinboardID?.uriRepresentation().absoluteString ?? "nil"
        let previewItem = previewItemID?.uriRepresentation().absoluteString ?? "nil"
        return
            "\(isSearchExpanded)-\(searchFocused)-\(isCreatingPinboard)-\(isPreviewPopoverPresented)-\(renameItem)-\(renamePinboard)-\(previewItem)"
    }
}
