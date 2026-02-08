import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func installKeyboardHandlers() {
        installReturnKeyHandler()
        installSpaceKeyHandler()
        installEscapeKeyHandler()
        installDeleteKeyHandler()
        installArrowKeyHandler()
    }

    func installReturnKeyHandler() {
        guard let window else { return }
        let handler: () -> Void = { [weak viewModel, weak modifierMonitor] in
            guard let viewModel, let modifierMonitor else { return }
            viewModel.handleReturnKey(
                orderedItems: self.filteredItems,
                isShiftPressed: modifierMonitor.isShiftPressed
            )
        }
        objc_setAssociatedObject(window, &ReturnKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }

    func installSpaceKeyHandler() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if pinboardRenameState.isCreating || pinboardRenameState.id != nil || renameItemID != nil {
                return false
            }
            if isSearchExpanded, searchFocused {
                return false
            }
            return previewCoordinator.togglePreviewForItem(
                nil,
                selectedItemIDs: viewModel.selectedItemIDs,
                onSelectionChange: viewModel.restoreSelection,
                filteredItems: filteredItems
            )
        }
        objc_setAssociatedObject(window, &SpaceKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }

    func installEscapeKeyHandler() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if previewCoordinator.isPreviewPopoverPresented {
                previewCoordinator.closePreview()
                return true
            }
            if pinboardRenameState.isCreating || pinboardRenameState.id != nil {
                handlePinboardCancel()
                return true
            }
            return false
        }
        objc_setAssociatedObject(window, &EscapeKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }

    func installDeleteKeyHandler() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { [weak viewModel] _ in
            // Don't delete when editing text
            if pinboardRenameState.isCreating || pinboardRenameState.id != nil || renameItemID != nil {
                return false
            }
            if isSearchExpanded, searchFocused {
                return false
            }
            guard let viewModel else { return false }
            // Need at least one selected item to delete
            guard !viewModel.selectedItemIDs.isEmpty else { return false }
            // Get first selected item to trigger deletion
            guard let firstSelectedID = viewModel.selectedItemIDs.first,
                  let item = filteredItems.first(where: { $0.objectID == firstSelectedID })
            else { return false }
            actionHandlers.deleteItem(
                item,
                selectedItemIDs: viewModel.selectedItemIDs,
                onClearSelection: viewModel.clearSelection
            )
            return true
        }
        objc_setAssociatedObject(window, &DeleteKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }
    
    func installArrowKeyHandler() {
        guard let window else { return }
        
        let handler: (NSEvent) -> Bool = { [weak viewModel] event in
            // Don't navigate when editing text or searching
            if pinboardRenameState.isCreating || pinboardRenameState.id != nil || renameItemID != nil {
                return false
            }
            if isSearchExpanded, searchFocused {
                return false
            }
            
            guard let viewModel else { return false }
            
            // Layout dependent navigation
            // Horizontal (bottom): Left/Right
            // Vertical (side): Up/Down
            
            let isHorizontal = overlayLayoutAxis == .horizontal
            let keyCode = event.keyCode
            
            // Left Arrow (123) / Right Arrow (124)
            // Up Arrow (126) / Down Arrow (125)
            
            var direction: Int?
            
            if isHorizontal {
                if keyCode == 123 { direction = -1 }      // Left -> Previous
                else if keyCode == 124 { direction = 1 }  // Right -> Next
            } else {
                if keyCode == 126 { direction = -1 }      // Up -> Previous
                else if keyCode == 125 { direction = 1 }  // Down -> Next
            }
            
            guard let moveDirection = direction else { return false }
            
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            viewModel.moveSelection(direction: moveDirection, in: filteredItems, isShiftPressed: isShiftPressed)
            return true
        }
        
        objc_setAssociatedObject(window, &ArrowKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }
}

