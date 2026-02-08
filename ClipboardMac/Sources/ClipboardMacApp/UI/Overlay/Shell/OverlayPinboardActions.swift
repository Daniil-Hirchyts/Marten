import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func handlePinboardSelect(_ id: UUID?) {
        closeSearchIfEmpty()
        withAnimation(.easeOut(duration: 0.14)) {
            searchModel.selectedPinboardID = id
        }
    }

    func handlePinboardCreateStart() {
        presentPinboardCreate()
    }

    func handleCreatePinboardFromVerticalPicker() {
        beginPinboardCreate(for: nil)
    }

    func presentPinboardCreate() {
        closeSearchIfEmpty()
        verticalPinboardDraftName = nextAvailablePinboardName()
        verticalPinboardDraftColor = nextAvailablePinboardColorHex()
        verticalPinboardDraftIcon = nil
        shouldPresentVerticalPinboardStylePicker = false
        isPinboardCreatePresented = true
    }

    func commitVerticalPinboardCreate() {
        let name = verticalPinboardDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didCreate = pinboardManager.createPinboard(
            name: name,
            colorHex: verticalPinboardDraftColor,
            iconName: verticalPinboardDraftIcon,
            pendingItem: pendingPinboardItem
        )
        guard didCreate else { return }

        pendingPinboardItem = nil
        isPinboardCreatePresented = false
        shouldPresentVerticalPinboardStylePicker = false

        DispatchQueue.main.async {
            let createdPinboard = visiblePinboards
                .sorted { $0.sortOrder > $1.sortOrder }
                .first(where: { $0.name == name })
            if let createdPinboard {
                withAnimation(.easeOut(duration: 0.14)) {
                    searchModel.selectedPinboardID = createdPinboard.id
                }
            }
        }
    }

    func cancelVerticalPinboardCreate() {
        isPinboardCreatePresented = false
        shouldPresentVerticalPinboardStylePicker = false
        pendingPinboardItem = nil
    }

    func presentVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        verticalPinboardEditDraftName = selectedCustomPinboard.name
        verticalPinboardEditDraftColor = selectedCustomPinboard.colorHex
        verticalPinboardEditDraftIcon = selectedCustomPinboard.iconName
        shouldPresentVerticalPinboardEditStylePicker = false
        isVerticalPinboardEditPresented = true
    }

    func commitVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        let name = verticalPinboardEditDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didSave = pinboardManager.renamePinboard(
            objectID: selectedCustomPinboard.objectID,
            name: name,
            colorHex: verticalPinboardEditDraftColor,
            iconName: verticalPinboardEditDraftIcon
        )
        guard didSave else { return }

        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func cancelVerticalPinboardEdit() {
        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func handleSetPinboardLock(_ pinboard: Pinboard, _ isEnabled: Bool) {
        lockHandler.setPinboardLock(pinboard, enabled: isEnabled)
    }

    func handleRequestPinboardUnlock(_ pinboard: Pinboard) {
        lockHandler.requestPinboardUnlock(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handleLockPinboardNow(_ pinboard: Pinboard) {
        lockHandler.lockPinboardNow(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handlePinboardRenameStart(_ pinboard: Pinboard) {
        renamePinboardID = pinboard.objectID
        renamePinboardName = pinboard.name
        renamePinboardColor = pinboard.colorHex
        renamePinboardIcon = pinboard.iconName
    }

    func handleDeletePinboard(_ pinboard: Pinboard) {
        searchModel.selectedPinboardID = actionHandlers.deletePinboard(
            pinboard,
            selectedPinboardID: searchModel.selectedPinboardID
        )
    }

    func handlePinboardReorder(_ dragged: Pinboard, _ target: Pinboard, insertBefore: Bool) {
        pinboardManager.optimisticReorderPinboards(
            dragged: dragged,
            target: target,
            insertBefore: insertBefore,
            visiblePinboards: visiblePinboards
        )
    }

    func handlePinboardMoveItem(_ pinboard: Pinboard, _ itemURIString: String) {
        guard pinboardLockController.canAccess(pinboardID: pinboard.id) else { return }
        pinboardManager.moveItemToPinboard(pinboard, itemURIString: itemURIString)
    }

    func handlePinboardCommit() {
        if isCreatingPinboard {
            let didCreate = actionHandlers.commitPinboardCreate(
                name: renamePinboardName,
                colorHex: renamePinboardColor,
                iconName: renamePinboardIcon,
                pendingItem: pendingPinboardItem
            )
            guard didCreate else { return }

            pendingPinboardItem = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isCreatingPinboard = false
            }
            renamePinboardIcon = nil
        } else if let objectID = renamePinboardID {
            let didRename = actionHandlers.commitPinboardRename(
                objectID: objectID,
                name: renamePinboardName,
                colorHex: renamePinboardColor,
                iconName: renamePinboardIcon
            )
            guard didRename else { return }

            renamePinboardID = nil
            renamePinboardIcon = nil
        }
    }

    func handlePinboardCancel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isCreatingPinboard = false
        }
        renamePinboardID = nil
        renamePinboardIcon = nil
    }

    func handlePinboardLayoutChange(_ layout: PinboardLayoutInfo) {
        DispatchQueue.main.async {
            frameCoordinator.updateCapturedPinboardLayout(layout)
            dragCoordinator.updatePinboardLayout(layout)
            let nextWidth = layout.contentWidth ?? 0
            if abs(pinboardTabsContentWidth - nextWidth) > 0.5 {
                pinboardTabsContentWidth = nextWidth
            }
        }
    }

    func handleMoveToPinboard(_ item: ClipItem, _ pinboard: Pinboard) {
        if !pinboardLockController.canAccess(pinboardID: pinboard.id) {
            handleRequestPinboardUnlock(pinboard)
            return
        }

        let selectedIDs = viewModel.selectedItemIDs
        if selectedIDs.count > 1, selectedIDs.contains(item.objectID) {
            let selectedItems = filteredItems.filter { selectedIDs.contains($0.objectID) }
            for selectedItem in selectedItems {
                actionHandlers.handleMoveToPinboard(selectedItem, pinboard)
            }
        } else {
            actionHandlers.handleMoveToPinboard(item, pinboard)
        }
    }

    func beginPinboardCreate(for item: ClipItem?) {
        pendingPinboardItem = item
        presentPinboardCreate()
    }
}
