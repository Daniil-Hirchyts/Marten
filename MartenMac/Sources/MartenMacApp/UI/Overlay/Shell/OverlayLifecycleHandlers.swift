import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import SwiftUI

extension OverlayShellView {
    func handleAppear() {
        searchFocused = true
        modifierMonitor.start()
        pinboardLockController.reconcile(validPinboardIDs: visiblePinboardIDs)
        ensureValidSelection()
        searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
        lastFilterInputHash = filterInputHash
        cachedFilteredItems = computeFilteredItems()
        dragCoordinator.ensurePreviewWindow()
        dragCoordinator.ensurePinboardPreviewWindow()
        installKeyboardHandlers()
    }

    func handleDisappear() {
        modifierMonitor.stop()
        dragCoordinator.cleanupPreviewWindow()
        dragCoordinator.cleanupPinboardPreviewWindow()
        previewCoordinator.closePreview()

        if searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchExpanded = false
            searchFocused = false
        }
        isFilterPopoverPresented = false
        pinboardRenameState.isCreating = false
        pinboardRenameState.id = nil
        pinboardRenameState.iconName = nil
        verticalPinboardCreateState.isPresented = false
        isVerticalPinboardDropdownPresented = false
        verticalPinboardCreateState.shouldPresentStylePicker = false
        verticalPinboardEditState.isPresented = false
        verticalPinboardEditState.shouldPresentStylePicker = false
    }

    func handleWindowChange(_ oldValue: NSWindow?, _ newValue: NSWindow?) {
        installKeyboardHandlers()
    }

    func handlePinboardSelectionChange(_ oldValue: UUID?, _ newValue: UUID?) {
        if oldValue != newValue {
            verticalPinboardEditState.isPresented = false
            verticalPinboardEditState.shouldPresentStylePicker = false
        }
        if isSelectedPinboardAwaitingUnlock {
            viewModel.clearSelection()
            previewCoordinator.closePreview()
            // Automatically trigger unlock when selecting a locked pinboard
            handleUnlockTap()
        }
        searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
    }

    func handlePinboardAccessibilityChange(_ isAccessible: Bool, _ old: Bool) {
        if !isAccessible, searchModel.selectedPinboardID != nil {
            viewModel.clearSelection()
            previewCoordinator.closePreview()
        }
    }

    func handleSearchExpandedChange(_ expanded: Bool, _ old: Bool) {
        if !expanded {
            isFilterPopoverPresented = false
        }
    }

    func handleFilterPopoverPresentedChange(_ oldValue: Bool, _ newValue: Bool) {
        guard newValue else { return }
        searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
    }

    func handleKeyHandlerRefresh(_ oldValue: String, _ newValue: String) {
        installKeyboardHandlers()
    }

    func handleVisiblePinboardsChange(_ oldValue: [UUID], _ newValue: [UUID]) {
        pinboardLockController.reconcile(validPinboardIDs: newValue)
        ensureValidSelection()
    }

    func handleItemsSourceAppsChange(_ oldValue: Int, _ newValue: Int) {
        searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
    }

    func handleFilteredItemsChange(_ oldValue: [URL], _ newValue: [URL]) {
        viewModel.ensureDefaultSelection(in: filteredItems)  // prunes stale selections only
    }

    func handleSelectionChange(_ oldValue: Set<NSManagedObjectID>, _ newValue: Set<NSManagedObjectID>) {
        if previewCoordinator.isPreviewPopoverPresented {
            previewCoordinator.closePreview()
        }
    }

    func handleOverlayLayoutAxisChange(_ oldValue: OverlayLayoutAxis, _ newValue: OverlayLayoutAxis) {
        if newValue == .vertical {
            frameCoordinator.clearCapturedPinboardLayout()
            dragCoordinator.clearPinboardLayoutState()
        }
    }

    func handleBroadcasterEvent(_ event: MartenEvent) {
        if event == .overlayDidShow {
            searchFocused = true
            announceOverlayItemCount()
        }
    }
}
