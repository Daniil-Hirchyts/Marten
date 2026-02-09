import MartenCore
import CoreData
import Foundation

@MainActor
protocol OverlayPasting: AnyObject {
    var selectedItemIDs: Set<NSManagedObjectID> { get }

    func paste(item: ClipItem, plainText: Bool)
    func pasteMultipleItems(_ items: [ClipItem], plainText: Bool)
}

extension OverlayViewModel: OverlayPasting {}

@MainActor
final class PasteStackManager {
    func pasteItemOrSelection(
        item: ClipItem,
        plainText: Bool,
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        viewModel: any OverlayPasting
    ) {
        if selectedItemIDs.count > 1 && selectedItemIDs.contains(item.objectID) {
            pasteSelection(
                selectedItemIDs: selectedItemIDs,
                orderedItems: orderedItems,
                plainText: plainText,
                viewModel: viewModel
            )
        } else {
            viewModel.paste(item: item, plainText: plainText)
        }
    }

    func pasteOutside(
        itemIDs: [NSManagedObjectID],
        plainText: Bool,
        orderedItems: [ClipItem],
        viewModel: any OverlayPasting
    ) {
        let draggedItems = orderedItems.filter { itemIDs.contains($0.objectID) }
        guard let firstItem = draggedItems.first else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if draggedItems.count == 1 {
                viewModel.paste(item: firstItem, plainText: plainText)
            } else {
                viewModel.pasteMultipleItems(draggedItems, plainText: plainText)
            }
        }
    }

    private func pasteSelection(
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        plainText: Bool,
        viewModel: any OverlayPasting
    ) {
        guard !selectedItemIDs.isEmpty else { return }
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        guard let firstItem = selectedItems.first else { return }

        if selectedItems.count == 1 {
            viewModel.paste(item: firstItem, plainText: plainText)
        } else {
            viewModel.pasteMultipleItems(selectedItems, plainText: plainText)
        }
    }
}
