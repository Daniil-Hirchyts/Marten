import CoreData
import MartenCore
import SwiftUI

#if canImport(UIKit)

struct ItemCardCollectionGridView: UIViewControllerRepresentable {
    let items: [ClipItem]
    let selectionModel: DashboardSelectionModel
    let canReorder: Bool
    let contentInsets: EdgeInsets
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void

    func makeUIViewController(context: Context) -> ItemCardCollectionViewController {
        let controller = ItemCardCollectionViewController(
            selectionModel: selectionModel,
            onTapItem: onTapItem,
            onCopyItem: onCopyItem,
            onCopyPlainTextItem: onCopyPlainTextItem,
            onPreviewItem: onPreviewItem,
            onShareItem: onShareItem,
            onMoveItem: onMoveItem,
            onDeleteItem: onDeleteItem,
            onReorderItems: onReorderItems
        )

        controller.update(
            items: items,
            canReorder: canReorder,
            isSelectionMode: selectionModel.isSelectionMode,
            selectedObjectIDs: selectionModel.selectedObjectIDs,
            contentInsets: UIEdgeInsets(
                top: contentInsets.top,
                left: contentInsets.leading,
                bottom: contentInsets.bottom,
                right: contentInsets.trailing
            )
        )

        return controller
    }

    func updateUIViewController(_ uiViewController: ItemCardCollectionViewController, context: Context) {
        uiViewController.update(
            items: items,
            canReorder: canReorder,
            isSelectionMode: selectionModel.isSelectionMode,
            selectedObjectIDs: selectionModel.selectedObjectIDs,
            contentInsets: UIEdgeInsets(
                top: contentInsets.top,
                left: contentInsets.leading,
                bottom: contentInsets.bottom,
                right: contentInsets.trailing
            )
        )
    }
}

#endif
