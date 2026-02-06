import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    var overlayScreenEdge: OverlayScreenEdge {
        OverlayScreenEdge(rawValue: overlayScreenEdgeRawValue) ?? OverlayLayoutSettings.defaultEdge
    }

    var overlayLayoutAxis: OverlayLayoutAxis {
        overlayScreenEdge.layoutAxis
    }

    var filteredItems: [ClipItem] {
        cachedFilteredItems
    }

    var filterInputHash: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.objectID)
        hasher.combine(items.last?.objectID)
        hasher.combine(searchModel.isSearchTextActive)
        hasher.combine(searchModel.searchResults.count)
        hasher.combine(searchModel.searchResults.first?.objectID)
        hasher.combine(searchModel.selectedPinboardID)
        hasher.combine(searchModel.dateFilter)
        hasher.combine(searchModel.typeFilters)
        hasher.combine(searchModel.appFilters)
        hasher.combine(lockedPinboardIDs)
        return hasher.finalize()
    }

    func computeFilteredItems() -> [ClipItem] {
        let selectedPinboardID = searchModel.selectedPinboardID
        let sourceItems = searchModel.isSearchTextActive ? searchModel.searchResults : Array(items)
        let baseList = sourceItems.filter { item in
            lockHandler.isItemVisible(item, selectedPinboardID: selectedPinboardID)
        }
        let filtered = searchModel.applyFilters(to: baseList)
        return actionHandlers.sortItems(filtered, selectedPinboardID: selectedPinboardID, allowPinning: allowPinning)
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
        let accessibleLocked = pinboardLockController.unlockedPinboardIDs
        let locked = pinboardLockController.lockedPinboardIDs
        return visiblePinboards.filter { pinboard in
            !locked.contains(pinboard.id) || accessibleLocked.contains(pinboard.id)
        }
    }

    var lockedPinboardIDs: Set<UUID> {
        let visibleIDs = Set(visiblePinboards.map(\.id))
        return pinboardLockController.lockedPinboardIDs
            .subtracting(pinboardLockController.unlockedPinboardIDs)
            .intersection(visibleIDs)
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
        searchModel.selectedPinboardID != nil
    }

    var isDragEnabled: Bool {
        !isSearchActive
    }

    var isReorderingEnabled: Bool {
        !isSearchActive && searchModel.selectedPinboardID != nil
    }

    var pinboardSelectionKey: String {
        searchModel.selectedPinboardID?.uuidString ?? "all"
    }

    var itemsChangeSignature: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.objectID)
        hasher.combine(items.last?.objectID)
        hasher.combine(items.first?.sourceAppBundleID)
        hasher.combine(items.last?.sourceAppBundleID)
        return hasher.finalize()
    }

    var keyHandlerRefreshToken: String {
        "\(isCreatingPinboard)-\(renamePinboardID?.description ?? "")-\(renameItemID?.description ?? "")-\(isSearchExpanded)-\(searchFocused)-\(previewCoordinator.isPreviewPopoverPresented)"
    }

}
