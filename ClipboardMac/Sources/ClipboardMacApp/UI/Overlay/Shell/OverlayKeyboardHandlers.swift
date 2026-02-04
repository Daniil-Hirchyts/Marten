import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func installKeyboardHandlers() {
        installReturnKeyHandler()
        installSpaceKeyHandler()
        installEscapeKeyHandler()
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
            if isCreatingPinboard || renamePinboardID != nil || renameItemID != nil {
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
            if isCreatingPinboard || renamePinboardID != nil {
                handlePinboardCancel()
                return true
            }
            return false
        }
        objc_setAssociatedObject(window, &EscapeKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }
}

