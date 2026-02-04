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
        actionHandlers.togglePin(item, allowPinning: allowPinning)
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
    }

    func handlePasteOutside(_ itemIDs: [NSManagedObjectID]) {
        pasteStackManager.pasteOutside(
            itemIDs: itemIDs,
            plainText: modifierMonitor.isShiftPressed,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }
}

