import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func handleAppear() {
        searchFocused = true
        modifierMonitor.start()
        pinboardLockController.reconcile(validPinboardIDs: visiblePinboardIDs)
        ensureValidSelection()
        lastFilterInputHash = filterInputHash
        cachedFilteredItems = computeFilteredItems()
        viewModel.ensureDefaultSelection(in: filteredItems)
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
        isCreatingPinboard = false
        renamePinboardID = nil
        renamePinboardIcon = nil
        isVerticalPinboardCreatePresented = false
        isVerticalPinboardDropdownPresented = false
        shouldPresentVerticalPinboardStylePicker = false
        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func handleWindowChange(_ oldValue: NSWindow?, _ newValue: NSWindow?) {
        installKeyboardHandlers()
    }

    func handlePinboardSelectionChange(_ oldValue: UUID?, _ newValue: UUID?) {
        if oldValue != newValue {
            isVerticalPinboardEditPresented = false
            shouldPresentVerticalPinboardEditStylePicker = false
        }
        if isSelectedPinboardAwaitingUnlock {
            viewModel.clearSelection()
            previewCoordinator.closePreview()
            // Automatically trigger unlock when selecting a locked pinboard
            handleUnlockTap()
        }
        if isFilterPopoverPresented {
            searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
        }
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

    func handleKeyHandlerRefresh(_ oldValue: String, _ newValue: String) {
        installKeyboardHandlers()
    }

    func handleVisiblePinboardsChange(_ oldValue: [UUID], _ newValue: [UUID]) {
        pinboardLockController.reconcile(validPinboardIDs: newValue)
        ensureValidSelection()
    }

    func handleItemsSourceAppsChange(_ oldValue: Int, _ newValue: Int) {
        if isFilterPopoverPresented {
            searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
        }
    }

    func handleFilteredItemsChange(_ oldValue: [URL], _ newValue: [URL]) {
        viewModel.ensureDefaultSelection(in: filteredItems)
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

    func handleBroadcasterEvent(_ event: ClipboardEvent) {
        if event == .overlayDidShow {
            searchFocused = true
            viewModel.ensureDefaultSelection(in: filteredItems)
            announceOverlayItemCount()
        }
    }
}
