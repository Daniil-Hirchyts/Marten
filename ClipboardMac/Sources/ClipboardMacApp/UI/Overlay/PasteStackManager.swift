import ClipboardCore
import CoreData
import Foundation

@MainActor
protocol OverlayPasting: AnyObject {
    var mode: OverlayMode { get }
    var selectedItemIDs: Set<NSManagedObjectID> { get }

    func setMode(_ mode: OverlayMode)
    func restoreSelection(_ ids: Set<NSManagedObjectID>, in orderedItems: [ClipItem])
    func paste(item: ClipItem, plainText: Bool)
    func pasteStack(plainText: Bool)
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
                plainText: plainText,
                selectedItemIDs: selectedItemIDs,
                orderedItems: orderedItems,
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
                if viewModel.mode == .browse {
                    viewModel.setMode(.pasteStack)
                    viewModel.restoreSelection(Set(itemIDs), in: draggedItems)
                }
                viewModel.pasteStack(plainText: plainText)
            }
        }
    }

    private func pasteSelection(
        plainText: Bool,
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        viewModel: any OverlayPasting
    ) {
        guard !selectedItemIDs.isEmpty else { return }
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        guard let firstItem = selectedItems.first else { return }

        if selectedItems.count == 1 {
            viewModel.paste(item: firstItem, plainText: plainText)
        } else {
            if viewModel.mode == .browse {
                let selectedIDs = viewModel.selectedItemIDs
                viewModel.setMode(.pasteStack)
                viewModel.restoreSelection(selectedIDs, in: orderedItems)
            }
            viewModel.pasteStack(plainText: plainText)
        }
    }
}
