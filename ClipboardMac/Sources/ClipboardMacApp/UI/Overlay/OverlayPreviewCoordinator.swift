import AppKit
@preconcurrency import ClipboardCore
import SwiftUI

/// Coordinates preview popover state and operations
@MainActor
public final class OverlayPreviewCoordinator: ObservableObject {
    @Published var previewItemID: NSManagedObjectID?
    @Published var isPreviewPopoverPresented = false

    private let itemEditorWindowController: ItemEditorWindowController

    init(itemEditorWindowController: ItemEditorWindowController) {
        self.itemEditorWindowController = itemEditorWindowController
    }

    func closePreview() {
        previewItemID = nil
        isPreviewPopoverPresented = false
    }

    func closeAllMenus() {
        closePreview()
    }

    func togglePreviewForItem(
        _ item: ClipItem?,
        selectedItemIDs: Set<NSManagedObjectID>,
        onSelectionChange: (Set<NSManagedObjectID>, [ClipItem]) -> Void,
        filteredItems: [ClipItem]
    ) -> Bool {
        let selected = item
            ?? filteredItems.first(where: { selectedItemIDs.contains($0.objectID) })
            ?? filteredItems.first

        guard let selected else {
            closePreview()
            return false
        }

        if !selectedItemIDs.contains(selected.objectID) {
            onSelectionChange([selected.objectID], filteredItems)
        }

        if isPreviewPopoverPresented, previewItemID == selected.objectID {
            closePreview()
            return true
        }

        previewItemID = selected.objectID
        isPreviewPopoverPresented = true
        return true
    }

    func openEditor(
        for item: ClipItem,
        closeOverlay: @escaping (@escaping () -> Void) -> Void
    ) {
        closePreview()

        closeOverlay { [itemEditorWindowController] in
            itemEditorWindowController.show(
                item: item,
                onSave: { _ in },
                onClose: {}
            )
        }
    }

    func closeEditor() {
        itemEditorWindowController.hide()
    }
}
