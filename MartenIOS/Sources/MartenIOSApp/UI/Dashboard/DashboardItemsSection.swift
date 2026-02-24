import CoreData
import MartenCore
import SwiftUI

struct DashboardItemsSection: View {
    @FetchRequest private var items: FetchedResults<ClipItem>
    let selectedPinboardID: UUID?
    let isItemVisible: (ClipItem) -> Bool
    @Bindable var selectionModel: DashboardSelectionModel
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onEditItem: (ClipItem) -> Void
    let onTogglePinItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void
    let onSwipeToNextPinboard: () -> Void
    let onSwipeToPreviousPinboard: () -> Void
    let onVisibleObjectIDsChanged: (Set<NSManagedObjectID>) -> Void

    init(
        selectedPinboardID: UUID?,
        isItemVisible: @escaping (ClipItem) -> Bool,
        selectionModel: DashboardSelectionModel,
        onTapItem: @escaping (ClipItem) -> Void,
        onCopyItem: @escaping (ClipItem) -> Void,
        onCopyPlainTextItem: @escaping (ClipItem) -> Void,
        onPreviewItem: @escaping (ClipItem) -> Void,
        onEditItem: @escaping (ClipItem) -> Void,
        onTogglePinItem: @escaping (ClipItem) -> Void,
        onShareItem: @escaping (ClipItem) -> Void,
        onMoveItem: @escaping (ClipItem) -> Void,
        onDeleteItem: @escaping (ClipItem) -> Void,
        onReorderItems: @escaping ([NSManagedObjectID]) -> Void,
        onSwipeToNextPinboard: @escaping () -> Void,
        onSwipeToPreviousPinboard: @escaping () -> Void,
        onVisibleObjectIDsChanged: @escaping (Set<NSManagedObjectID>) -> Void
    ) {
        _items = FetchRequest(
            fetchRequest: dashboardItemsFetchRequest(selectedPinboardID: selectedPinboardID),
            animation: .default
        )
        self.selectedPinboardID = selectedPinboardID
        self.isItemVisible = isItemVisible
        self.selectionModel = selectionModel
        self.onTapItem = onTapItem
        self.onCopyItem = onCopyItem
        self.onCopyPlainTextItem = onCopyPlainTextItem
        self.onPreviewItem = onPreviewItem
        self.onEditItem = onEditItem
        self.onTogglePinItem = onTogglePinItem
        self.onShareItem = onShareItem
        self.onMoveItem = onMoveItem
        self.onDeleteItem = onDeleteItem
        self.onReorderItems = onReorderItems
        self.onSwipeToNextPinboard = onSwipeToNextPinboard
        self.onSwipeToPreviousPinboard = onSwipeToPreviousPinboard
        self.onVisibleObjectIDsChanged = onVisibleObjectIDsChanged
    }

    var body: some View {
        ItemCardGridView(
            items: visibleItems,
            selectionModel: selectionModel,
            canReorder: selectedPinboardID != nil,
            allowPinning: selectedPinboardID != nil,
            contentInsets: EdgeInsets(top: 80, leading: 0, bottom: 100, trailing: 0),
            onTapItem: onTapItem,
            onCopyItem: onCopyItem,
            onCopyPlainTextItem: onCopyPlainTextItem,
            onPreviewItem: onPreviewItem,
            onEditItem: onEditItem,
            onTogglePinItem: onTogglePinItem,
            onShareItem: onShareItem,
            onMoveItem: onMoveItem,
            onDeleteItem: onDeleteItem,
            onReorderItems: onReorderItems,
            onSwipeToNextPinboard: onSwipeToNextPinboard,
            onSwipeToPreviousPinboard: onSwipeToPreviousPinboard
        )
        .onAppear {
            onVisibleObjectIDsChanged(Set(visibleItems.map(\.objectID)))
        }
        .onChange(of: itemsSignature) {
            onVisibleObjectIDsChanged(Set(visibleItems.map(\.objectID)))
        }
    }

    private var visibleItems: [ClipItem] {
        Array(items).filter(isItemVisible)
    }

    private var itemsSignature: String {
        items.map { item in
            "\(item.objectID.uriRepresentation().absoluteString)-\(item.modifiedAt.timeIntervalSince1970)"
        }
        .joined(separator: "|")
    }
}
