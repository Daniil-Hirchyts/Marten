import MartenCore
import CoreData
import SwiftUI

struct ItemCardGridView: View {
    let items: [ClipItem]
    let selectionModel: DashboardSelectionModel
    let canReorder: Bool
    let onTapItem: (ClipItem) -> Void
    let onCopyItem: (ClipItem) -> Void
    let onCopyPlainTextItem: (ClipItem) -> Void
    let onPreviewItem: (ClipItem) -> Void
    let onShareItem: (ClipItem) -> Void
    let onMoveItem: (ClipItem) -> Void
    let onDeleteItem: (ClipItem) -> Void
    let onReorderItems: ([NSManagedObjectID]) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var orderedItems: [ClipItem] = []
    @State private var draggingItemID: NSManagedObjectID?
    @State private var sweepState = SweepSelectionState()
    @State private var dragPileIDs: Set<NSManagedObjectID> = []

    private let gridCoordinateSpace = "itemCardGrid"

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 150, maximum: 500), spacing: 12, alignment: .top),
            count: count
        )
    }

    /// Total count for the drag pile badge (primary dragged card + piled cards).
    private var dragGroupCount: Int {
        guard draggingItemID != nil else { return 0 }
        return 1 + dragPileIDs.count
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("No Items Yet", systemImage: "tray")
            } description: {
                Text("Tap + to create your first item, or paste from the clipboard.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayedItems, id: \.objectID) { item in
                        cardCell(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(MartenAnimation.smooth, value: displayedItems.map(\.objectID))
                .onPreferenceChange(CardFramePreferenceKey.self) { frames in
                    sweepState.updateFrames(frames)
                }
            }
            .coordinateSpace(name: gridCoordinateSpace)
            .scrollIndicators(.hidden)
            .overlay { sweepGestureOverlay }
            .onAppear {
                orderedItems = items
            }
            .onChange(of: items.map(\.objectID)) {
                if draggingItemID == nil {
                    orderedItems = items
                }
            }
            .onChange(of: draggingItemID) {
                if draggingItemID == nil {
                    dragPileIDs.removeAll()
                }
            }
        }
    }

    // MARK: - Card Cell

    @ViewBuilder
    private func cardCell(for item: ClipItem) -> some View {
        let isDragPrimary = draggingItemID == item.objectID
        let isInPile = dragPileIDs.contains(item.objectID)

        ItemCardView(
            item: item,
            isSelectionMode: selectionModel.isSelectionMode,
            isSelected: selectionModel.isSelected(item),
            dragPayload: selectionModel.dragPayload(for: item),
            onTap: { handleTap(item) },
            onCopy: { onCopyItem(item) },
            onCopyPlainText: { onCopyPlainTextItem(item) },
            onPreview: { onPreviewItem(item) },
            onShare: { onShareItem(item) },
            onMove: { onMoveItem(item) },
            onDelete: { onDeleteItem(item) },
            isInDragPile: isInPile,
            dragPileCount: isDragPrimary ? dragGroupCount : 0
        )
        .opacity(isDragPrimary ? 0.5 : (isInPile ? 0.6 : 1.0))
        .reportCardFrame(objectID: item.objectID, coordinateSpace: gridCoordinateSpace)
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
            dragPileIDs: $dragPileIDs,
            canReorder: canReorder,
            isSelectionMode: selectionModel.isSelectionMode,
            onReorderCommit: { ids in
                onReorderItems(ids)
            }
        ))
        .transition(MartenAnimation.fadeScale)
    }

    // MARK: - Tap Handling

    private func handleTap(_ item: ClipItem) {
        // When dragging in reorder mode, taps add/remove from drag pile
        if draggingItemID != nil && canReorder && !selectionModel.isSelectionMode {
            guard item.objectID != draggingItemID else { return }
            if dragPileIDs.contains(item.objectID) {
                dragPileIDs.remove(item.objectID)
            } else {
                dragPileIDs.insert(item.objectID)
            }
            return
        }
        onTapItem(item)
    }

    // MARK: - Sweep Selection Overlay

    @ViewBuilder
    private var sweepGestureOverlay: some View {
        if selectionModel.isSelectionMode {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .named(gridCoordinateSpace))
                        .onChanged { value in
                            let dx = abs(value.translation.width)
                            let dy = abs(value.translation.height)

                            // If drag is primarily vertical, don't activate sweep (let ScrollView scroll)
                            if !sweepState.isActive && dy > dx * 1.5 {
                                return
                            }

                            // Activate on first horizontal-enough movement
                            if !sweepState.isActive {
                                sweepState.isActive = true
                                // Determine add/remove mode from first touched card
                                if let firstID = sweepState.objectID(at: value.startLocation) {
                                    sweepState.addsToSelection = !selectionModel.selectedObjectIDs.contains(firstID)
                                    // Toggle the first card
                                    if let firstItem = displayedItems.first(where: { $0.objectID == firstID }) {
                                        selectionModel.toggleSelection(for: firstItem)
                                        sweepState.sweptObjectIDs.insert(firstID)
                                    }
                                }
                            }

                            // Hit-test current location
                            if let hitID = sweepState.objectID(at: value.location),
                               !sweepState.sweptObjectIDs.contains(hitID),
                               let hitItem = displayedItems.first(where: { $0.objectID == hitID }) {
                                sweepState.sweptObjectIDs.insert(hitID)
                                let isCurrentlySelected = selectionModel.selectedObjectIDs.contains(hitID)
                                if sweepState.addsToSelection && !isCurrentlySelected {
                                    selectionModel.toggleSelection(for: hitItem)
                                } else if !sweepState.addsToSelection && isCurrentlySelected {
                                    selectionModel.toggleSelection(for: hitItem)
                                }
                            }
                        }
                        .onEnded { _ in
                            sweepState.isActive = false
                            sweepState.sweptObjectIDs.removeAll()
                        }
                )
                .allowsHitTesting(selectionModel.isSelectionMode)
        }
    }

    // MARK: - Helpers

    private var displayedItems: [ClipItem] {
        draggingItemID != nil ? orderedItems : items
    }
}

// MARK: - Drop Delegate

private struct ItemCardDropDelegate: DropDelegate {
    let targetItem: ClipItem
    @Binding var orderedItems: [ClipItem]
    @Binding var draggingItemID: NSManagedObjectID?
    @Binding var dragPileIDs: Set<NSManagedObjectID>
    let canReorder: Bool
    let isSelectionMode: Bool
    let onReorderCommit: ([NSManagedObjectID]) -> Void

    func dropEntered(info: DropInfo) {
        guard canReorder, !isSelectionMode else { return }
        guard let draggingItemID else { return }
        guard draggingItemID != targetItem.objectID else { return }
        // Don't rearrange within the pile
        guard !dragPileIDs.contains(targetItem.objectID) else { return }

        // Collect all IDs in the drag group (primary + pile)
        let dragGroupIDs: Set<NSManagedObjectID> = dragPileIDs.union([draggingItemID])

        // Find the target index
        guard let toIndex = orderedItems.firstIndex(where: { $0.objectID == targetItem.objectID }) else {
            return
        }

        // Find the primary dragged item's current index for direction determination
        guard let primaryFromIndex = orderedItems.firstIndex(where: { $0.objectID == draggingItemID }) else {
            return
        }

        let movingDown = toIndex > primaryFromIndex

        withAnimation(MartenAnimation.quick) {
            // Remove all drag group items
            let groupItems = orderedItems.filter { dragGroupIDs.contains($0.objectID) }
            orderedItems.removeAll { dragGroupIDs.contains($0.objectID) }

            // Re-find target index after removal
            if let newToIndex = orderedItems.firstIndex(where: { $0.objectID == targetItem.objectID }) {
                let insertIndex = movingDown ? newToIndex + 1 : newToIndex
                let clampedIndex = min(insertIndex, orderedItems.count)
                orderedItems.insert(contentsOf: groupItems, at: clampedIndex)
            }
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
        dragPileIDs.removeAll()
        draggingItemID = nil

        return true
    }

    func dropExited(info: DropInfo) {
        // Optional: Handle any cleanup when drag exits
    }
}
