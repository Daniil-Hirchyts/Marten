import CoreData
import MartenCore
import SwiftUI

#if canImport(UIKit)

struct ItemCardCollectionGridView: UIViewControllerRepresentable {
    let items: [ClipItem]
    let selectionModel: DashboardSelectionModel
    let canReorder: Bool
    let allowPinning: Bool
    let contentInsets: EdgeInsets
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onEditItem: (ClipItem) -> Void
    let onConvertTypeItem: (ClipItem, ItemType) -> Void
    let onTogglePinItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void
    let onSwipeToNextPinboard: () -> Void
    let onSwipeToPreviousPinboard: () -> Void

    func makeUIViewController(context: Context) -> ItemCardCollectionViewController {
        let controller = ItemCardCollectionViewController(
            selectionModel: selectionModel,
            onTapItem: onTapItem,
            onCopyItem: onCopyItem,
            onCopyPlainTextItem: onCopyPlainTextItem,
            onPreviewItem: onPreviewItem,
            onEditItem: onEditItem,
            onConvertTypeItem: onConvertTypeItem,
            onTogglePinItem: onTogglePinItem,
            onShareItem: onShareItem,
            onMoveItem: onMoveItem,
            onDeleteItem: onDeleteItem,
            onReorderItems: onReorderItems,
            onSwipeToNextPinboard: onSwipeToNextPinboard,
            onSwipeToPreviousPinboard: onSwipeToPreviousPinboard
        )

        controller.update(
            items: items,
            canReorder: canReorder,
            allowPinning: allowPinning,
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
            allowPinning: allowPinning,
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
