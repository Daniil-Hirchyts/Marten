import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
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
        withAnimation(OverlayAnimation.cardSpring) {
            actionHandlers.togglePin(item, allowPinning: allowPinning)
            cachedFilteredItems = computeFilteredItems()
        }
    }

    func handleConvertItemType(_ item: ClipItem, to newType: ItemType) {
        withAnimation(OverlayAnimation.cardSpring) {
            actionHandlers.convertItemType(item, to: newType)
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
        // During an active drag, force toggle behavior so clicking adds/removes from the drag group
        let forceToggle = dragCoordinator.dragPreviewData != nil
        // Read modifier state live from NSEvent.modifierFlags rather than the cached ModifierKeyMonitor
        // value, which can get stuck as `true` if a key-release flagsChanged event fires while the
        // overlay is not the key window (e.g. right after dismissing a context menu).
        let flags = NSEvent.modifierFlags
        viewModel.selectItem(
            item,
            in: filteredItems,
            isShiftPressed: flags.contains(.shift),
            isCommandPressed: forceToggle || flags.contains(.command)
        )
    }

    func handleCardDoubleTap(_ item: ClipItem) {
        // Prevent paste during an active drag
        guard dragCoordinator.dragPreviewData == nil else { return }
        closeSearchIfEmpty()
        viewModel.paste(item: item, plainText: NSEvent.modifierFlags.contains(.shift))
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
