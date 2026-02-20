import MartenCore
import CoreData
import SwiftUI

struct ItemCardGridView: View {
    let items: [ClipItem]
    let selectionModel: DashboardSelectionModel
    let canReorder: Bool
    let allowPinning: Bool
    var contentInsets: EdgeInsets = .init()
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onTogglePinItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void
    let onSwipeToNextPinboard: () -> Void
    let onSwipeToPreviousPinboard: () -> Void
    private let pinboardSwipeMinDistance: CGFloat = 55

    #if !canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var orderedItems: [ClipItem] = []
    @State private var draggingItemID: NSManagedObjectID?

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 150, maximum: 500), spacing: 12, alignment: .top),
            count: count
        )
    }
    #endif

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("No Items Yet", systemImage: "tray")
            } description: {
                Text("Tap + to create your first item, or paste from the clipboard.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded(handlePinboardSwipe)
            )
        } else {
            #if canImport(UIKit)
            ItemCardCollectionGridView(
                items: items,
                selectionModel: selectionModel,
                canReorder: canReorder,
                allowPinning: allowPinning,
                contentInsets: contentInsets,
                onTapItem: onTapItem,
                onCopyItem: onCopyItem,
                onCopyPlainTextItem: onCopyPlainTextItem,
                onPreviewItem: onPreviewItem,
                onTogglePinItem: onTogglePinItem,
                onShareItem: onShareItem,
                onMoveItem: onMoveItem,
                onDeleteItem: onDeleteItem,
                onReorderItems: onReorderItems,
                onSwipeToNextPinboard: onSwipeToNextPinboard,
                onSwipeToPreviousPinboard: onSwipeToPreviousPinboard
            )
            #else
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayedItems, id: \.objectID) { item in
                        cardCell(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(MartenAnimation.smooth, value: displayedItems.map(\.objectID))
            }
            .scrollIndicators(.hidden)
            .onDrop(of: [.text], delegate: GridFallbackDropDelegate(
                draggingItemID: $draggingItemID
            ))
            .onAppear {
                orderedItems = items
            }
            .onChange(of: items.map(\.objectID)) {
                draggingItemID = nil
                orderedItems = items
            }
            #endif
        }
    }

    private func handlePinboardSwipe(_ value: DragGesture.Value) {
        let horizontalTranslation = value.translation.width
        let verticalTranslation = value.translation.height

        guard abs(horizontalTranslation) > abs(verticalTranslation) else { return }
        guard abs(horizontalTranslation) >= pinboardSwipeMinDistance else { return }

        if horizontalTranslation < 0 {
            onSwipeToNextPinboard()
        } else {
            onSwipeToPreviousPinboard()
        }
    }

    #if !canImport(UIKit)
    @ViewBuilder
    private func cardCell(for item: ClipItem) -> some View {
        ItemCardView(
            item: item,
            isSelectionMode: selectionModel.isSelectionMode,
            isSelected: selectionModel.isSelected(item),
            allowPinning: allowPinning,
            onTap: { handleTap(item) },
            onCopy: { onCopyItem(item) },
            onCopyPlainText: { onCopyPlainTextItem(item) },
            onPreview: { onPreviewItem(item) },
            onTogglePin: { onTogglePinItem(item) },
            onShare: { onShareItem(item) },
            onMove: { onMoveItem(item) },
            onDelete: { onDeleteItem(item) }
        )
        .onDrag {
            if canReorder && !selectionModel.isSelectionMode {
                draggingItemID = item.objectID
                return NSItemProvider(object: item.objectID.uriRepresentation().absoluteString as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.text], delegate: ItemCardDropDelegate(
            targetItem: item,
            orderedItems: $orderedItems,
            draggingItemID: $draggingItemID,
            canReorder: canReorder,
            isSelectionMode: selectionModel.isSelectionMode,
            onReorderCommit: { ids in
                onReorderItems(ids)
            }
        ))
        .transition(MartenAnimation.fadeScale)
    }

    private func handleTap(_ item: ClipItem) {
        if draggingItemID != nil {
            draggingItemID = nil
            return
        }
        onTapItem(item)
    }

    private var displayedItems: [ClipItem] {
        draggingItemID != nil ? orderedItems : items
    }
    #endif
}

#if !canImport(UIKit)
private struct ItemCardDropDelegate: DropDelegate {
    let targetItem: ClipItem
    @Binding var orderedItems: [ClipItem]
    @Binding var draggingItemID: NSManagedObjectID?
    let canReorder: Bool
    let isSelectionMode: Bool
    let onReorderCommit: ([NSManagedObjectID]) -> Void

    func dropEntered(info: DropInfo) {
        guard canReorder, !isSelectionMode else { return }
        guard let draggingItemID else { return }
        guard draggingItemID != targetItem.objectID else { return }

        guard let fromIndex = orderedItems.firstIndex(where: { $0.objectID == draggingItemID }),
              let toIndex = orderedItems.firstIndex(where: { $0.objectID == targetItem.objectID }) else {
            return
        }

        withAnimation(MartenAnimation.quick) {
            orderedItems.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder, !isSelectionMode else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder, !isSelectionMode else { return false }
        guard draggingItemID != nil else { return false }

        let orderedIDs = orderedItems.map(\.objectID)
        onReorderCommit(orderedIDs)
        draggingItemID = nil

        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct GridFallbackDropDelegate: DropDelegate {
    @Binding var draggingItemID: NSManagedObjectID?

    func performDrop(info: DropInfo) -> Bool {
        draggingItemID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggingItemID != nil ? .move : .cancel)
    }
}
#endif
