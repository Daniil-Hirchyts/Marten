import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import OSLog
import SwiftUI

extension OverlayShellView {
    func handlePinboardSelect(_ id: UUID?) {
        closeSearchIfEmpty()
        withAnimation(OverlayAnimation.pinboardSelect) {
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
        verticalPinboardCreateState.draftName = nextAvailablePinboardName()
        verticalPinboardCreateState.draftColorHex = nextAvailablePinboardColorHex()
        verticalPinboardCreateState.draftIconName = nil
        verticalPinboardCreateState.shouldPresentStylePicker = false
        verticalPinboardCreateState.isPresented = true
    }

    func commitVerticalPinboardCreate() {
        let name = verticalPinboardCreateState.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didCreate = pinboardManager.createPinboard(
            name: name,
            colorHex: verticalPinboardCreateState.draftColorHex,
            iconName: verticalPinboardCreateState.draftIconName,
            pendingItem: pinboardRenameState.pendingItem
        )
        guard didCreate else { return }

        pinboardRenameState.pendingItem = nil
        verticalPinboardCreateState.isPresented = false
        verticalPinboardCreateState.shouldPresentStylePicker = false

        DispatchQueue.main.async {
            let createdPinboard = visiblePinboards
                .sorted { $0.sortOrder > $1.sortOrder }
                .first(where: { $0.name == name })
            if let createdPinboard {
                withAnimation(OverlayAnimation.pinboardSelect) {
                    searchModel.selectedPinboardID = createdPinboard.id
                }
            }
        }
    }

    func cancelVerticalPinboardCreate() {
        verticalPinboardCreateState.isPresented = false
        verticalPinboardCreateState.shouldPresentStylePicker = false
        pinboardRenameState.pendingItem = nil
    }

    func presentVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        verticalPinboardEditState.draftName = selectedCustomPinboard.name
        verticalPinboardEditState.draftColorHex = selectedCustomPinboard.colorHex
        verticalPinboardEditState.draftIconName = selectedCustomPinboard.iconName
        verticalPinboardEditState.shouldPresentStylePicker = false
        verticalPinboardEditState.isPresented = true
    }

    func commitVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        let name = verticalPinboardEditState.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didSave = pinboardManager.renamePinboard(
            objectID: selectedCustomPinboard.objectID,
            name: name,
            colorHex: verticalPinboardEditState.draftColorHex,
            iconName: verticalPinboardEditState.draftIconName
        )
        guard didSave else { return }

        verticalPinboardEditState.isPresented = false
        verticalPinboardEditState.shouldPresentStylePicker = false
    }

    func cancelVerticalPinboardEdit() {
        verticalPinboardEditState.isPresented = false
        verticalPinboardEditState.shouldPresentStylePicker = false
    }

    func handleSetPinboardLock(_ pinboard: Pinboard, _ isEnabled: Bool) {
        guard pinboardManager.canLockPinboard(pinboard) else { return }
        lockHandler.setPinboardLock(pinboard, enabled: isEnabled)
    }

    func handleRequestPinboardUnlock(_ pinboard: Pinboard) {
        lockHandler.requestPinboardUnlock(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handleLockPinboardNow(_ pinboard: Pinboard) {
        lockHandler.lockPinboardNow(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handlePinboardRenameStart(_ pinboard: Pinboard) {
        pinboardRenameState.id = pinboard.objectID
        pinboardRenameState.name = pinboard.name
        pinboardRenameState.colorHex = pinboard.colorHex
        pinboardRenameState.iconName = pinboard.iconName
    }

    func handleDeletePinboard(_ pinboard: Pinboard) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(pinboard.name)\"?"
        alert.informativeText = "This pinboard will be permanently deleted. Items inside will remain in All."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

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
        if pinboardRenameState.isCreating {
            let didCreate = actionHandlers.commitPinboardCreate(
                name: pinboardRenameState.name,
                colorHex: pinboardRenameState.colorHex,
                iconName: pinboardRenameState.iconName,
                pendingItem: pinboardRenameState.pendingItem
            )
            guard didCreate else { return }

            pinboardRenameState.pendingItem = nil
            withAnimation(OverlayAnimation.pinboardSpring) {
                pinboardRenameState.isCreating = false
            }
            pinboardRenameState.iconName = nil
        } else if let objectID = pinboardRenameState.id {
            let didRename = actionHandlers.commitPinboardRename(
                objectID: objectID,
                name: pinboardRenameState.name,
                colorHex: pinboardRenameState.colorHex,
                iconName: pinboardRenameState.iconName
            )
            guard didRename else { return }

            pinboardRenameState.id = nil
            pinboardRenameState.iconName = nil
        }
    }

    func handlePinboardCancel() {
        withAnimation(OverlayAnimation.pinboardSpring) {
            pinboardRenameState.isCreating = false
        }
        pinboardRenameState.id = nil
        pinboardRenameState.iconName = nil
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
        pinboardRenameState.pendingItem = item
        presentPinboardCreate()
    }

    // MARK: - Sharing Actions

    func handleSharePinboard(_ pinboard: Pinboard) {
        shareSheetPinboard = pinboard
    }

    func handleManageSharing(_ pinboard: Pinboard) {
        shareSheetPinboard = pinboard
    }

    func handleStopSharing(_ pinboard: Pinboard) {
        let alert = NSAlert()
        alert.messageText = "Stop sharing this pinboard?"
        alert.informativeText = "All participant access will be removed immediately."
        alert.alertStyle = .warning
        let stopButton = alert.addButton(withTitle: "Stop Sharing")
        stopButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await sharingRepository?.stopSharing(pinboardID: pinboard.objectID)
                } catch {
                    Logger.ui.error("Failed to stop sharing: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
    }

    func handleLeaveSharedPinboard(_ pinboard: Pinboard) {
        guard let sharing = sharingRepository else { return }
        let wasSelected = searchModel.selectedPinboardID == pinboard.id
        Task {
            do {
                try await sharing.leaveShare(pinboardID: pinboard.objectID)
                if wasSelected {
                    await MainActor.run {
                        searchModel.selectedPinboardID = nil
                    }
                }
            } catch {
                Logger.ui.error("Failed to leave shared pinboard: \(error.localizedDescription, privacy: .private)")
                NSSound.beep()
            }
        }
    }
}
