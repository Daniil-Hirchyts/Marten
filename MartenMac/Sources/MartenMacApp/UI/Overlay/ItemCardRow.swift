import AppKit
import MartenCore
import MartenMacServices
import CoreData
import SwiftUI

struct ItemCardRow: View {
    private let cardSpacing: CGFloat = 12
    private let placeholderWidth: CGFloat = 3
    private let localCoordinateSpaceName = "ItemRowLocalSpace"

    let items: [ClipItem]
    let pinboardSelectionKey: String
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let selectedPinboardID: UUID?
    let mode: OverlayMode
    let selectedItemIDs: Set<NSManagedObjectID>
    let editingItemID: NSManagedObjectID?
    let allowPinning: Bool
    let readOnly: Bool
    let clipItemEditor: any ClipItemEditing
    let isDragEnabled: Bool
    let isReorderingEnabled: Bool
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onCommitRename: (ClipItem, String) -> Void
    let onTap: (ClipItem) -> Void
    let onDoubleTap: (ClipItem) -> Void
    let onReorder: ([NSManagedObjectID], ClipItem, Bool) -> Void
    let onReorderEnd: () -> Void
    let onDropToPinboard: (ClipItem, NSManagedObjectID) -> Void
    let onDropToAll: (ClipItem) -> Void
    let onPasteOutside: ([NSManagedObjectID]) -> Void
    var onBeginNativeDrag: (([NSManagedObjectID]) -> Bool)? = nil
    var isNativeDragActive: (() -> Bool)? = nil
    var onPinboardDropTargetChanged: ((NSManagedObjectID?) -> Void)? = nil
    let coordinateSpaceName: String
    let pinboardFrames: [NSManagedObjectID: CGRect]
    let allPinboardFrame: CGRect?
    let window: NSWindow?
    @Binding var dragPreviewData: DragPreviewData?
    var onPreviewUpdate: ((DragPreviewData?) -> Void)? = nil  // Direct preview update, bypasses state

    @Binding var previewItemID: NSManagedObjectID?
    @Binding var isPreviewPopoverPresented: Bool

    @EnvironmentObject private var frameCoordinator: FrameCoordinator

    @State private var itemFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var rowFrame: CGRect = .zero
    @State private var dragState: DragState?
    @State private var dragOpacity: Double = 0
    @State private var dragSnapshotImage: NSImage?
    @State private var centeringTimer: Timer?
    @State private var dropTarget: DropTarget?
    @State private var pinboardDropTarget: PinboardDropTarget?
    @State private var isMeasuringItemFrames = false
    @State private var loadedItemCount: Int = 0
    @State private var lastVisibleIndex: Int = 0
    @State private var currentPage: Int = 0
    @State private var rowContainerSize: CGSize = CGSize(width: 0, height: 320)

    @StateObject private var itemFramesBuffer = ItemFramesBuffer()


    var body: some View {
        // Keep card size stable from cached container dimensions to avoid per-frame geometry reads.
        let verticalPadding: CGFloat = 12
        let cardSize = max(120, rowContainerSize.height - (verticalPadding * 2))
        let sideMargin: CGFloat = 14
        let placeholderInset = sideMargin + (placeholderWidth / 2)
        let paginationEnabled = ItemCardRowPagination.isEnabled(
            totalCount: items.count, isReorderingEnabled: isReorderingEnabled)
        let initialLoadedCount = ItemCardRowPagination.initialLoadedCount(
            total: items.count, isEnabled: paginationEnabled)
        let effectiveLoadedCount = min(max(loadedItemCount, initialLoadedCount), items.count)
        let visibleItems = Array(items.prefix(effectiveLoadedCount))

        Group {
            if #available(macOS 14.0, *) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        LazyHStack(alignment: .center, spacing: cardSpacing) {
                            cardViews(size: cardSize, proxy: proxy, items: visibleItems)
                        }
                        .padding(.vertical, verticalPadding)
                        .animation(
                            dragState != nil
                                ? .spring(response: 0.32, dampingFraction: 0.86)
                                : nil,
                            value: visibleItemsOrderSignature(visibleItems)
                        )
                        .onChange(of: pinboardSelectionKey) { _, _ in
                            if let firstID = visibleItems.first?.objectID {
                                proxy.scrollTo(firstID, anchor: .leading)
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, placeholderInset, for: .scrollContent)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        LazyHStack(alignment: .center, spacing: cardSpacing) {
                            cardViews(size: cardSize, proxy: proxy, items: visibleItems)
                        }
                        .padding(.vertical, verticalPadding)
                        .animation(
                            dragState != nil
                                ? .spring(response: 0.32, dampingFraction: 0.86)
                                : nil,
                            value: visibleItemsOrderSignature(visibleItems)
                        )
                        .padding(.horizontal, placeholderInset)
                        .onChange(of: pinboardSelectionKey) { _, _ in
                            if let firstID = visibleItems.first?.objectID {
                                proxy.scrollTo(firstID, anchor: .leading)
                            }
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: localCoordinateSpaceName)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ItemRowFrameKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
            }
        )
        .overlay(alignment: .topLeading) {
            placeholderView()
        }
        .onPreferenceChange(ItemFrameKey.self) { frames in
            itemFramesBuffer.submit(frames) { latest in
                applyItemFramesPreference(latest)
            }
        }
        .onPreferenceChange(ItemRowFrameKey.self) { frame in
            frameCoordinator.updateLatestItemRowFrame(frame)
            // Skip reactive updates during drag
            guard dragState == nil else { return }
            // Only update if significantly changed
            if !rectsApproximatelyEqual(frame, rowFrame) {
                rowFrame = frame
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ItemRowContainerSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ItemRowContainerSizeKey.self) { size in
            guard abs(size.height - rowContainerSize.height) > 0.5
                || abs(size.width - rowContainerSize.width) > 0.5
            else {
                return
            }
            rowContainerSize = size
        }
        // Note: All preview updates now happen directly via callback in drag handlers and timer
        // This avoids triggering parent re-renders through the binding
        .onChange(of: itemsSignature) { _, _ in
            // Reset item frames when items change (e.g., after search clears or filter changes)
            // This ensures the drag gesture works with fresh frame data
            let currentIDs = Set(itemFrames.keys)
            let newIDSet = Set(items.map(\.objectID))
            if currentIDs != newIDSet {
                itemFrames = [:]
                frameCoordinator.clearLatestItemFrames()
            }

            let paginationEnabled = ItemCardRowPagination.isEnabled(
                totalCount: items.count, isReorderingEnabled: isReorderingEnabled)
            let initialLoadedCount = ItemCardRowPagination.initialLoadedCount(
                total: items.count, isEnabled: paginationEnabled)
            if loadedItemCount == 0 {
                loadedItemCount = initialLoadedCount
            } else {
                loadedItemCount = min(max(loadedItemCount, initialLoadedCount), items.count)
            }
            lastVisibleIndex = min(lastVisibleIndex, max(0, items.count - 1))
            currentPage = ItemCardRowPagination.page(for: lastVisibleIndex)
        }
        .onAppear {
            let paginationEnabled = ItemCardRowPagination.isEnabled(
                totalCount: items.count, isReorderingEnabled: isReorderingEnabled)
            loadedItemCount = ItemCardRowPagination.initialLoadedCount(
                total: items.count, isEnabled: paginationEnabled)
            lastVisibleIndex = 0
            currentPage = 0
        }
        .onChange(of: pinboardSelectionKey) { _, _ in
            dropTarget = nil
            pinboardDropTarget = nil
            dragState = nil
            isMeasuringItemFrames = false
            itemFrames = [:]
            frameCoordinator.clearLatestItemFrames()
        }
    }

    private var itemsSignature: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.objectID)
        hasher.combine(items.last?.objectID)
        hasher.combine(selectedPinboardID)
        return hasher.finalize()
    }

    private func visibleItemsOrderSignature(_ visibleItems: [ClipItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(visibleItems.count)
        if let first = visibleItems.first {
            hasher.combine(first.objectID)
            hasher.combine(first.displayOrder)
        }
        if let last = visibleItems.last {
            hasher.combine(last.objectID)
            hasher.combine(last.displayOrder)
        }
        return hasher.finalize()
    }


    private func applyItemFramesPreference(_ frames: [NSManagedObjectID: CGRect]) {
        frameCoordinator.updateLatestItemFrames(frames)

        guard dragState == nil else { return }

        let countChanged = frames.count != itemFrames.count
        let keysChanged = Set(frames.keys) != Set(itemFrames.keys)
        if countChanged || keysChanged {
            itemFrames = frames
        }
    }

    @ViewBuilder
    private func cardViews(size: CGFloat, proxy: ScrollViewProxy?, items: [ClipItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.objectID) { index, item in
            let isDragging = dragState?.itemIDs.contains(item.objectID) ?? false

            let isPreviewPresented = Binding(
                get: {
                    isPreviewPopoverPresented && previewItemID == item.objectID
                },
                set: { newValue in
                    if !newValue {
                        if previewItemID == item.objectID {
                            previewItemID = nil
                        }
                        isPreviewPopoverPresented = false
                    }
                }
            )

            let base = ItemCard(
                item: item,
                pinboards: pinboards,
                lockedPinboardIDs: lockedPinboardIDs,
                selectedPinboardID: selectedPinboardID,
                itemPinboardSignature: pinboardSignature(for: item),
                isSelected: selectedItemIDs.contains(item.objectID),
                isEditing: editingItemID == item.objectID,
                badgeIndex: badgeIndex(for: index),
                isDropTarget: false,
                showPinIndicator: allowPinning,
                allowPinning: allowPinning,
                readOnly: readOnly,
                isDragEnabled: isDragEnabled,
                cardSize: size,
                onPaste: onPaste,
                onPastePlainText: onPastePlainText,
                onCopy: onCopy,
                onDelete: onDelete,
                onTogglePin: onTogglePin,
                onMoveToPinboard: onMoveToPinboard,
                onCreatePinboard: onCreatePinboard,
                onEdit: onEdit,
                onRename: onRename,
                onCommitRename: onCommitRename,
                onTap: { tappedItem in
                    withAnimation {
                        proxy?.scrollTo(tappedItem.objectID)
                    }
                    // During drag, toggle tapped item in/out of the drag group
                    if let state = dragState {
                        let tappedID = tappedItem.objectID
                        // Can't remove the primary (initiating) item
                        if tappedID != state.primaryItemID {
                            if let idx = state.itemIDs.firstIndex(of: tappedID) {
                                var ids = state.itemIDs
                                ids.remove(at: idx)
                                dragState = DragState(
                                    itemIDs: ids,
                                    primaryItemID: state.primaryItemID,
                                    pointerLocation: state.pointerLocation,
                                    baseCenter: state.baseCenter,
                                    translation: state.translation
                                )
                            } else {
                                var ids = state.itemIDs
                                ids.append(tappedID)
                                dragState = DragState(
                                    itemIDs: ids,
                                    primaryItemID: state.primaryItemID,
                                    pointerLocation: state.pointerLocation,
                                    baseCenter: state.baseCenter,
                                    translation: state.translation
                                )
                            }
                            updateDragPreview(useCallback: true)
                        }
                    }
                    onTap(tappedItem)
                },
                onDoubleTap: onDoubleTap
            )
            .popover(isPresented: isPreviewPresented, arrowEdge: .bottom) {
                OverlayItemPreview(
                    item: item,
                    allowPinning: allowPinning,
                    pinboards: pinboards,
                    lockedPinboardIDs: lockedPinboardIDs,
                    clipItemEditor: clipItemEditor,
                    onEdit: { editedItem in
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                        onEdit(editedItem)
                    },
                    onPaste: { pastedItem in
                        onPaste(pastedItem)
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                    },
                    onPastePlainText: { pastedItem in
                        onPastePlainText(pastedItem)
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                    },
                    onCopy: { copiedItem in
                        onCopy(copiedItem)
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                    },
                    onTogglePin: { toggledItem in
                        onTogglePin(toggledItem)
                    },
                    onMoveToPinboard: { movedItem, pinboard in
                        onMoveToPinboard(movedItem, pinboard)
                    },
                    onCreatePinboard: { sourceItem in
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                        onCreatePinboard(sourceItem)
                    },
                    onDelete: { deletedItem in
                        onDelete(deletedItem)
                        previewItemID = nil
                        isPreviewPopoverPresented = false
                    }
                )
                .frame(
                    width: item.shouldUseLargePreviewPopover ? 920 : 560,
                    height: item.shouldUseLargePreviewPopover ? 640 : 380
                )
            }
            .frame(width: size, height: size)
            .opacity(isDragging ? 0.25 : 1)
            .background(
                Group {
                    if isMeasuringItemFrames || dragState != nil {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ItemFrameKey.self,
                                value: [
                                    item.objectID: proxy.frame(in: .named(localCoordinateSpaceName))
                                ]
                            )
                        }
                    }
                }
            )
            .onAppear {
                lastVisibleIndex = max(lastVisibleIndex, index)
                currentPage = ItemCardRowPagination.page(for: lastVisibleIndex)

                let paginationEnabled = ItemCardRowPagination.isEnabled(
                    totalCount: self.items.count, isReorderingEnabled: isReorderingEnabled)
                let initialLoadedCount = ItemCardRowPagination.initialLoadedCount(
                    total: self.items.count, isEnabled: paginationEnabled)
                let currentLoadedCount = min(
                    max(loadedItemCount, initialLoadedCount), self.items.count)
                let nextLoadedCount = ItemCardRowPagination.nextLoadedCount(
                    currentLoadedCount: currentLoadedCount,
                    visibleIndex: index,
                    totalCount: self.items.count,
                    isEnabled: paginationEnabled
                )
                if nextLoadedCount != loadedItemCount {
                    loadedItemCount = nextLoadedCount
                }
            }

            if isDragEnabled {
                base.simultaneousGesture(dragGesture(for: item))
            } else {
                base
            }
        }
    }

    private func dragGesture(for item: ClipItem) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(localCoordinateSpaceName))
            .onChanged { value in
                handleDragChanged(item: item, value: value)
            }
            .onEnded { value in
                handleDragEnded(item: item, value: value)
            }
    }

    private func handleDragChanged(item: ClipItem, value: DragGesture.Value) {
        guard isDragEnabled else { return }
        // Bail out if a native drag session is handling events
        if isNativeDragActive?() == true { return }

        if let dragState, !dragState.itemIDs.contains(item.objectID) {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )
        let overlayPointer = overlayPointerLocation(localPointer: localPointer)

        if dragState == nil {
            // Use latest frames from non-reactive storage
            guard let frame = frameCoordinator.latestItemFrames[item.objectID] else {
                isMeasuringItemFrames = true
                return
            }

            // Sync reactive state with latest frames
            itemFrames = frameCoordinator.latestItemFrames
            rowFrame = frameCoordinator.latestItemRowFrame

            let draggedID = item.objectID
            let itemIDs: [NSManagedObjectID]

            if selectedItemIDs.contains(draggedID) {
                itemIDs = orderedObjectIDs(for: selectedItemIDs)
            } else {
                itemIDs = [draggedID]
            }

            // Capture card snapshot from the overlay for instant AppKit display
            if let window {
                let cardOverlayRect = CGRect(
                    x: frame.origin.x + rowFrame.minX,
                    y: frame.origin.y + rowFrame.minY,
                    width: frame.width,
                    height: frame.height
                )
                dragSnapshotImage = captureCardSnapshot(from: window, cardRect: cardOverlayRect)
            }

            dragState = DragState(
                itemIDs: itemIDs,
                primaryItemID: draggedID,
                pointerLocation: overlayPointer,
                baseCenter: CGPoint(x: frame.midX, y: frame.midY),
                translation: .zero
            )
            dragOpacity = 1

            // Set binding for parent state (isGlobalDragActive etc.)
            updateDragPreview(useCallback: false)
            // Also call callback directly to create the preview window immediately
            // (Option A: eliminates one-frame delay — window appears on first drag event)
            updateDragPreview(useCallback: true)
            // Clear snapshot after first use — SwiftUI renders on top by the next event
            dragSnapshotImage = nil

            // Set initial centering offset (will animate to zero) - stored non-reactively
            frameCoordinator.setDragCenteringOffset(
                CGSize(
                    width: value.startLocation.x - frame.midX,
                    height: value.startLocation.y - frame.midY
                )
            )

            // Start centering animation timer - updates non-reactive offset and preview window directly
            centeringTimer?.invalidate()
            var iterationCount = 0
            let maxIterations = 120 // Safety cap: ~2 seconds at 60 FPS
            centeringTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) {
                [self] timer in
                Task { @MainActor [self] in
                    iterationCount += 1
                    let easing: CGFloat = 0.2
                    let current = frameCoordinator.dragCenteringOffset
                    let nextX = current.width * (1 - easing)
                    let nextY = current.height * (1 - easing)

                    if (abs(nextX) < 0.5 && abs(nextY) < 0.5) || iterationCount >= maxIterations {
                        frameCoordinator.setDragCenteringOffset(.zero)
                        timer.invalidate()
                        centeringTimer = nil
                    } else {
                        frameCoordinator.setDragCenteringOffset(CGSize(width: nextX, height: nextY))
                    }
                    updateDragPreview(useCallback: true)
                }
            }

        } else if var state = dragState {
            state.pointerLocation = overlayPointer
            state.translation = value.translation
            dragState = state
            // Update preview directly using callback (bypasses SwiftUI state)
            updateDragPreview(useCallback: true)
        }

        // Update drop targets WITHOUT animation for better performance
        let previousDropTarget = dropTarget
        let previousPinboardDropTarget = pinboardDropTarget

        if let pinboardTarget = computePinboardDropTarget(overlayLocation: overlayPointer) {
            pinboardDropTarget = pinboardTarget
            dropTarget = nil
        } else if isReorderingEnabled {
            pinboardDropTarget = nil
            let target = computeDropTarget(
                location: localPointer, draggedIDs: dragState?.itemIDs ?? [item.objectID])
            dropTarget = target
        } else {
            dropTarget = nil
        }

        if dropTarget != previousDropTarget && dropTarget != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } else if pinboardDropTarget != previousPinboardDropTarget && pinboardDropTarget != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        // Propagate pinboard drop target to tab bar for visual highlight
        if pinboardDropTarget != previousPinboardDropTarget {
            let targetID: NSManagedObjectID? = {
                switch pinboardDropTarget {
                case .pinboard(let id): return id
                case .all: return PinboardTabBarIDs.allTabObjectID
                case nil: return nil
                }
            }()
            onPinboardDropTargetChanged?(targetID)
        }

        // Transition to native drag when mouse leaves the overlay window
        if let window, let dragState {
            let mouseLocation = NSEvent.mouseLocation
            if !window.frame.contains(mouseLocation) {
                if let onBeginNativeDrag, onBeginNativeDrag(dragState.itemIDs) {
                    centeringTimer?.invalidate()
                    centeringTimer = nil
                    frameCoordinator.setDragCenteringOffset(.zero)
                    dropTarget = nil
                    pinboardDropTarget = nil
                    dragOpacity = 0
                    onPinboardDropTargetChanged?(nil)
                    self.dragState = nil
                    isMeasuringItemFrames = false
                    itemFrames = [:]
                    frameCoordinator.clearLatestItemFrames()
                    return
                }
            }
        }
    }

    private func handleDragEnded(item: ClipItem, value: DragGesture.Value) {
        // Skip if a native drag session took over
        if isNativeDragActive?() == true { return }

        guard isDragEnabled else { return }

        guard let dragState,
            dragState.primaryItemID == item.objectID
        else {
            return
        }

        guard dragState.primaryItemID == item.objectID else { return }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )
        let overlayPointer = overlayPointerLocation(localPointer: localPointer)

        var handled = false

        if let pinboardTarget = computePinboardDropTarget(overlayLocation: overlayPointer) {
            switch pinboardTarget {
            case .all:
                for itemID in dragState.itemIDs {
                    if let draggedItem = items.first(where: { $0.objectID == itemID }) {
                        onDropToAll(draggedItem)
                    }
                }
            case .pinboard(let pinboardID):
                for itemID in dragState.itemIDs {
                    if let draggedItem = items.first(where: { $0.objectID == itemID }) {
                        onDropToPinboard(draggedItem, pinboardID)
                    }
                }
            }
            handled = true
        } else if isReorderingEnabled,
            let target = computeDropTarget(
                location: localPointerLocation(from: overlayPointer), draggedIDs: dragState.itemIDs)
        {
            onReorder(dragState.itemIDs, target.item, target.insertBefore)
            onReorderEnd()
            handled = true
        }

        // Check if dropped outside the overlay window (skip if native drag handled it)
        if !handled, let window = window, isNativeDragActive?() != true {
            let mouseLocation = NSEvent.mouseLocation
            let windowFrame = window.frame

            // Check if mouse is outside the window bounds
            if !windowFrame.contains(CGPoint(x: mouseLocation.x, y: mouseLocation.y)) {
                onPasteOutside(dragState.itemIDs)
            }
        }

        centeringTimer?.invalidate()
        centeringTimer = nil

        endDrag(for: dragState.primaryItemID)
    }

    private func endDrag(for itemID: NSManagedObjectID) {
        // Stop centering timer
        centeringTimer?.invalidate()
        centeringTimer = nil
        frameCoordinator.setDragCenteringOffset(.zero)

        dropTarget = nil
        pinboardDropTarget = nil
        dragOpacity = 0
        dragSnapshotImage = nil
        onPinboardDropTargetChanged?(nil)

        // Hide the preview window — must send nil explicitly (not just opacity 0)
        // so the window is ordered out and recreated fresh for the next drag.
        if let callback = onPreviewUpdate {
            callback(nil)
        } else {
            dragPreviewData = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if dragState?.primaryItemID == itemID {
                dragState = nil
                isMeasuringItemFrames = false
                itemFrames = [:]
                frameCoordinator.clearLatestItemFrames()
            }
        }
    }

    private func computeDropTarget(location: CGPoint, draggedIDs: [NSManagedObjectID])
        -> DropTarget?
    {
        let allOrdered = orderedFrames()
        let ordered = allOrdered.filter { frame in
            !draggedIDs.contains(frame.item.objectID)
        }

        guard !ordered.isEmpty,
            let first = ordered.first,
            let last = ordered.last
        else {
            return nil
        }

        let locationX = location.x
        let candidate: DropTarget?

        if locationX < first.frame.minX {
            let placeholderX = placeholderX(for: ordered, targetIndex: 0, insertBefore: true)
            candidate = DropTarget(item: first.item, insertBefore: true, placeholderX: placeholderX)
        } else if locationX > last.frame.maxX {
            let placeholderX = placeholderX(
                for: ordered, targetIndex: ordered.count - 1, insertBefore: false)
            candidate = DropTarget(item: last.item, insertBefore: false, placeholderX: placeholderX)
        } else if let hit = ordered.first(where: {
            $0.frame.minX <= locationX && locationX <= $0.frame.maxX
        }) {
            let insertBefore = locationX < hit.frame.midX
            let targetIndex =
                ordered.firstIndex(where: { $0.item.objectID == hit.item.objectID }) ?? 0
            let placeholderX = placeholderX(
                for: ordered, targetIndex: targetIndex, insertBefore: insertBefore)
            candidate = DropTarget(
                item: hit.item, insertBefore: insertBefore, placeholderX: placeholderX)
        } else if let next = ordered.first(where: { locationX < $0.frame.minX }) {
            let targetIndex =
                ordered.firstIndex(where: { $0.item.objectID == next.item.objectID }) ?? 0
            let placeholderX = placeholderX(
                for: ordered, targetIndex: targetIndex, insertBefore: true)
            candidate = DropTarget(item: next.item, insertBefore: true, placeholderX: placeholderX)
        } else {
            candidate = nil
        }

        // Hide placeholder if dropping would keep the card in its original position
        guard let candidate else { return nil }

        // Get the frames of the dragged items
        let draggedFrames = draggedIDs.compactMap { itemFrames[$0] }
        guard !draggedFrames.isEmpty else { return candidate }

        // Calculate the span where dragged cards originated
        let draggedMinX = draggedFrames.map(\.minX).min() ?? 0
        let draggedMaxX = draggedFrames.map(\.maxX).max() ?? 0

        // Check if placeholder falls within or adjacent to the original dragged card position
        // Add a small margin (half of cardSpacing) to account for the gap
        let margin = cardSpacing / 2
        if candidate.placeholderX >= (draggedMinX - margin)
            && candidate.placeholderX <= (draggedMaxX + margin)
        {
            return nil
        }

        return candidate
    }

    private func placeholderX(
        for ordered: [(item: ClipItem, frame: CGRect)], targetIndex: Int, insertBefore: Bool
    ) -> CGFloat {
        if insertBefore {
            if targetIndex > 0 {
                let previous = ordered[targetIndex - 1].frame
                let current = ordered[targetIndex].frame
                return (previous.maxX + current.minX) / 2
            }
            return ordered[targetIndex].frame.minX - cardSpacing / 2
        }

        if targetIndex + 1 < ordered.count {
            let current = ordered[targetIndex].frame
            let next = ordered[targetIndex + 1].frame
            return (current.maxX + next.minX) / 2
        }

        return ordered[targetIndex].frame.maxX + cardSpacing / 2
    }

    private func computePinboardDropTarget(overlayLocation: CGPoint) -> PinboardDropTarget? {
        // Use captured frames from the shared coordinator, adjusted by scroll delta
        let capturedAllFrame = frameCoordinator.capturedAllPinboardFrame
        let capturedFrames = frameCoordinator.capturedPinboardFrames
        let capturedOffset = frameCoordinator.capturedPinboardScrollOffset
        let currentOffset = frameCoordinator.currentPinboardScrollOffset

        // Calculate scroll delta (positive = scrolled right, frames moved left)
        let scrollDelta = currentOffset - capturedOffset

        // If captured frames exist, use them with scroll adjustment
        if !capturedFrames.isEmpty || capturedAllFrame != nil {
            // Check "All" tab (adjusted for scroll)
            if let capturedAllFrame {
                var adjustedFrame = capturedAllFrame
                adjustedFrame.origin.x += scrollDelta
                if adjustedFrame.contains(overlayLocation) {
                    return .all
                }
            }

            // Check individual pinboards (adjusted for scroll)
            for (pinboardID, capturedFrame) in capturedFrames {
                var adjustedFrame = capturedFrame
                adjustedFrame.origin.x += scrollDelta
                if adjustedFrame.contains(overlayLocation) {
                    return .pinboard(pinboardID)
                }
            }
        } else {
            // Fallback: use passed frames directly (no scroll adjustment needed as they're current)
            if let allPinboardFrame, allPinboardFrame.contains(overlayLocation) {
                return .all
            }

            for (pinboardID, frame) in pinboardFrames {
                if frame.contains(overlayLocation) {
                    return .pinboard(pinboardID)
                }
            }
        }

        return nil
    }

    private func overlayPointerLocation(localPointer: CGPoint) -> CGPoint {
        // Try window-based conversion first (more accurate)
        if let window, let pointer = overlayPointerLocation(from: window) {
            return pointer
        }
        // Fallback to row frame offset
        return CGPoint(x: localPointer.x + rowFrame.minX, y: localPointer.y + rowFrame.minY)
    }

    private func localPointerLocation(from overlayPointer: CGPoint) -> CGPoint {
        CGPoint(x: overlayPointer.x - rowFrame.minX, y: overlayPointer.y - rowFrame.minY)
    }

    private func overlayPointerLocation(from window: NSWindow) -> CGPoint? {
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let layout = window.contentLayoutRect
        guard layout.width > 0, layout.height > 0 else { return nil }
        return CGPoint(
            x: windowPoint.x - layout.minX,
            y: layout.maxY - windowPoint.y
        )
    }

    private func orderedFrames() -> [(item: ClipItem, frame: CGRect)] {
        items.compactMap { item in
            guard let frame = itemFrames[item.objectID] else { return nil }
            return (item: item, frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        if let dropTarget, let frame = itemFrames[dropTarget.item.objectID] {
            let height = max(0, frame.height - 16)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 8)
                .transition(.opacity)
        }
    }

    private func badgeIndex(for index: Int) -> Int? {
        guard mode == .browse, index < 9 else { return nil }
        return index + 1
    }

    private func orderedObjectIDs(for ids: Set<NSManagedObjectID>) -> [NSManagedObjectID] {
        items.compactMap { item in
            ids.contains(item.objectID) ? item.objectID : nil
        }
    }

    private func updateDragPreview(useCallback: Bool = false) {
        guard let dragState else {
            if useCallback, let callback = onPreviewUpdate {
                callback(nil)
            } else {
                dragPreviewData = nil
            }
            return
        }

        let draggedItems = dragState.itemIDs.compactMap { id in
            items.first { $0.objectID == id }
        }
        let cardSize = itemFrames[dragState.primaryItemID]?.width ?? 0

        let previewPosition = CGPoint(
            x: dragState.baseCenter.x + dragState.translation.width + rowFrame.minX
                + frameCoordinator.dragCenteringOffset.width,
            y: dragState.baseCenter.y + dragState.translation.height + rowFrame.minY
                + frameCoordinator.dragCenteringOffset.height
        )

        let data = DragPreviewData(
            items: draggedItems,
            pinboards: pinboards,
            cardSize: cardSize,
            position: previewPosition,
            opacity: dragOpacity,
            snapshotImage: dragSnapshotImage
        )

        // Use callback to update preview directly (bypasses SwiftUI state, no re-renders)
        if useCallback, let callback = onPreviewUpdate {
            callback(data)
        } else {
            dragPreviewData = data
        }
    }
}

@MainActor
private final class ItemFramesBuffer: ObservableObject {
    private var pending: [NSManagedObjectID: CGRect]?
    private var scheduled = false

    func submit(
        _ frames: [NSManagedObjectID: CGRect],
        apply: @escaping @MainActor ([NSManagedObjectID: CGRect]) -> Void
    ) {
        pending = frames
        guard !scheduled else { return }
        scheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            guard let latest = self.pending else { return }
            self.pending = nil
            apply(latest)
        }
    }
}

private struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] { [:] }

    static func reduce(
        value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ItemRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ItemRowContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct DragPreviewData: Equatable {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let cardSize: CGFloat
    let position: CGPoint
    let opacity: Double
    let isCompactLayout: Bool
    /// Card snapshot captured from the overlay for instant AppKit display.
    var snapshotImage: NSImage?

    init(items: [ClipItem], pinboards: [Pinboard], cardSize: CGFloat, position: CGPoint, opacity: Double, isCompactLayout: Bool = false, snapshotImage: NSImage? = nil) {
        self.items = items
        self.pinboards = pinboards
        self.cardSize = cardSize
        self.position = position
        self.opacity = opacity
        self.isCompactLayout = isCompactLayout
        self.snapshotImage = snapshotImage
    }

    // snapshotImage is excluded: it's a transient one-frame value used only for the
    // initial AppKit placeholder and cleared immediately after, so changes to it
    // should not trigger SwiftUI equality checks or re-renders.
    static func == (lhs: DragPreviewData, rhs: DragPreviewData) -> Bool {
        lhs.items.map { $0.objectID } == rhs.items.map { $0.objectID }
            && lhs.pinboards.map { $0.objectID } == rhs.pinboards.map { $0.objectID }
            && lhs.cardSize == rhs.cardSize && lhs.position == rhs.position
            && lhs.opacity == rhs.opacity && lhs.isCompactLayout == rhs.isCompactLayout
    }
}

private struct DropTarget: Equatable {
    let item: ClipItem
    let insertBefore: Bool
    let placeholderX: CGFloat

    static func == (lhs: DropTarget, rhs: DropTarget) -> Bool {
        lhs.item.objectID == rhs.item.objectID && lhs.insertBefore == rhs.insertBefore
            && lhs.placeholderX == rhs.placeholderX
    }
}

struct ItemCardDragPreview: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let cardSize: CGFloat

    var body: some View {
        ItemCard(
            item: item,
            pinboards: pinboards,
            lockedPinboardIDs: [],
            selectedPinboardID: nil,
            isSelected: false,
            isEditing: false,
            badgeIndex: nil,
            isDropTarget: false,
            showPinIndicator: false,
            allowPinning: false,
            readOnly: false,
            isDragEnabled: false,
            cardSize: cardSize,
            onPaste: { _ in },
            onPastePlainText: { _ in },
            onCopy: { _ in },
            onDelete: { _ in },
            onTogglePin: { _ in },
            onMoveToPinboard: { _, _ in },
            onCreatePinboard: { _ in },
            onEdit: { _ in },
            onRename: { _ in },
            onCommitRename: { _, _ in },
            onTap: { _ in },
            onDoubleTap: { _ in }
        )
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
        .accessibilityHidden(true)
    }
}

struct MultiItemCardDragPreview: View {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let cardSize: CGFloat

    private let stackOffset: CGFloat = 4
    private let maxVisibleCards = 3
    private static let stackRotations: [Double] = [0, 2.5, -3]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.prefix(maxVisibleCards).enumerated()), id: \.offset) {
                index, item in
                ItemCard(
                    item: item,
                    pinboards: pinboards,
                    lockedPinboardIDs: [],
                    selectedPinboardID: nil,
                    isSelected: false,
                    isEditing: false,
                    badgeIndex: nil,
                    isDropTarget: false,
                    showPinIndicator: false,
                    allowPinning: false,
                    readOnly: false,
                    isDragEnabled: false,
                    cardSize: cardSize,
                    onPaste: { _ in },
                    onPastePlainText: { _ in },
                    onCopy: { _ in },
                    onDelete: { _ in },
                    onTogglePin: { _ in },
                    onMoveToPinboard: { _, _ in },
                    onCreatePinboard: { _ in },
                    onEdit: { _ in },
                    onRename: { _ in },
                    onCommitRename: { _, _ in },
                    onTap: { _ in },
                    onDoubleTap: { _ in }
                )
                .frame(width: cardSize, height: cardSize)
                .rotationEffect(.degrees(Self.stackRotations[min(index, Self.stackRotations.count - 1)]))
                .offset(
                    x: CGFloat(index) * stackOffset,
                    y: CGFloat(index) * stackOffset
                )
                .opacity(0.9 - (Double(index) * 0.1))
            }

            if items.count > maxVisibleCards {
                Text("\(items.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                            .shadow(radius: 2)
                    )
                    .offset(x: cardSize - 30, y: -8)
            }
        }
        .scaleEffect(0.96)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ItemCardRowPagination {
    static let thresholdCount: Int = 100
    static let batchSize: Int = 50
    static let preloadBuffer: Int = 10

    static func isEnabled(totalCount: Int, isReorderingEnabled: Bool) -> Bool {
        totalCount > thresholdCount && !isReorderingEnabled
    }

    static func initialLoadedCount(total: Int, isEnabled: Bool) -> Int {
        guard isEnabled else { return total }
        return min(batchSize, total)
    }

    static func nextLoadedCount(
        currentLoadedCount: Int, visibleIndex: Int, totalCount: Int, isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return totalCount }
        let preloadStartIndex = max(0, currentLoadedCount - preloadBuffer)
        guard visibleIndex >= preloadStartIndex else { return currentLoadedCount }
        return min(currentLoadedCount + batchSize, totalCount)
    }

    static func page(for index: Int) -> Int {
        guard index >= 0 else { return 0 }
        return index / batchSize
    }
}
