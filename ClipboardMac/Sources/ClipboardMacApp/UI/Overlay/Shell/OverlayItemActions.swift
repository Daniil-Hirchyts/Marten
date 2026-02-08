import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func handleItemPaste(_ item: ClipItem) {
        pasteStackManager.pasteItemOrSelection(
            item: item,
            plainText: false,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }

    func handleItemPastePlainText(_ item: ClipItem) {
        pasteStackManager.pasteItemOrSelection(
            item: item,
            plainText: true,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }

    func handleCopyItem(_ item: ClipItem) {
        actionHandlers.copyItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            filteredItems: filteredItems,
            eventBroadcaster: eventBroadcaster
        )
    }

    func handleDeleteItem(_ item: ClipItem) {
        actionHandlers.deleteItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            onClearSelection: viewModel.clearSelection
        )
    }

    func handleTogglePin(_ item: ClipItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            actionHandlers.togglePin(item, allowPinning: allowPinning)
            cachedFilteredItems = computeFilteredItems()
        }
    }

    func handleOpenEditor(_ item: ClipItem) {
        previewCoordinator.openEditor(for: item, closeOverlay: viewModel.closeOverlayForSettings)
    }

    func handleCommitItemRename(item: ClipItem, newTitle: String) {
        actionHandlers.commitItemRename(item: item, newTitle: newTitle)
        renameItemID = nil
    }

    func handleCardTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.selectItem(
            item,
            in: filteredItems,
            isShiftPressed: modifierMonitor.isShiftPressed,
            isCommandPressed: modifierMonitor.isCommandPressed
        )
    }

    func handleCardDoubleTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.paste(item: item, plainText: modifierMonitor.isShiftPressed)
    }

    func handleReorderItems(_ draggedIDs: [NSManagedObjectID], _ target: ClipItem, insertBefore: Bool) {
        actionHandlers.reorderItems(
            draggedIDs,
            target,
            insertBefore: insertBefore,
            filteredItems: filteredItems,
            isSearchActive: isSearchActive
        )
        cachedFilteredItems = computeFilteredItems()
    }

    func handlePasteOutside(_ itemIDs: [NSManagedObjectID]) {
        pasteStackManager.pasteOutside(
            itemIDs: itemIDs,
            plainText: modifierMonitor.isShiftPressed,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }

    func handleBeginNativeDrag(_ itemIDs: [NSManagedObjectID]) -> Bool {
        let items = filteredItems.filter { itemIDs.contains($0.objectID) }
        guard !items.isEmpty else { return false }

        let vm = viewModel
        let started = dragCoordinator.beginNativeDrag(
            from: window,
            items: items,
            plainText: modifierMonitor.isShiftPressed,
            onCompleted: {},
            onEnded: {
                // Close the overlay after the native drag session ends.
                // We can't close it earlier because the NSDraggingSession
                // requires its source view (the panel's contentView) to
                // remain in a valid window hierarchy.
                vm.closeOverlayForSettings {}
            }
        )

        if started {
            // Visually hide the overlay so the user can focus on the target
            // app's drop zone, but keep the panel ordered-in so the dragging
            // session's source view stays valid.
            window?.alphaValue = 0
        }

        return started
    }
}
