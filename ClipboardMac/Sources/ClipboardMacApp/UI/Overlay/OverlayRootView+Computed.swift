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
        visiblePinboards.filter { pinboardLockController.canAccess(pinboardID: $0.id) }
    }

    var lockedPinboardIDs: Set<UUID> {
        Set(visiblePinboards.filter { !pinboardLockController.canAccess(pinboardID: $0.id) }.map(\.id))
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

    var itemsSourceAppsHash: Int {
        let apps = Set(items.compactMap(\.sourceAppBundleID))
        return apps.reduce(0) { $0 ^ $1.hashValue }
    }

    var keyHandlerRefreshToken: String {
        "\(isCreatingPinboard)-\(renamePinboardID?.description ?? "")-\(renameItemID?.description ?? "")-\(isSearchExpanded)-\(searchFocused)-\(previewCoordinator.isPreviewPopoverPresented)"
    }
}
