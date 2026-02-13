import AppKit
import MartenCore
import MartenMacServices
import CoreData
import SwiftUI

struct ItemCompactColumn: View {
    private let rowSpacing: CGFloat = 8
    private let placeholderHeight: CGFloat = 3
    private let localCoordinateSpaceName = "ItemCompactColumnLocalSpace"
    private let scrollCoordinateSpaceName = "ItemCompactColumnScrollSpace"

    let items: [ClipItem]
    let pinboardSelectionKey: String
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
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
    var onPreviewUpdate: ((DragPreviewData?) -> Void)? = nil
    @Binding var previewItemID: NSManagedObjectID?
    @Binding var isPreviewPopoverPresented: Bool

    @EnvironmentObject private var frameCoordinator: FrameCoordinator

    @State private var rowFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var columnFrame: CGRect = .zero
    @State private var dragState: DragState?
    @State private var dropTarget: DropTarget?
    @State private var pinboardDropTarget: PinboardDropTarget?
    @State private var dragOpacity: Double = 0
    @State private var dragSnapshotImage: NSImage?
    @State private var pendingRowFrames: [NSManagedObjectID: CGRect]?
    @State private var isRowFrameUpdateScheduled = false
    @State private var isMeasuringRowFrames = false
    @State private var loadedItemCount: Int = 0
    @State private var lastVisibleIndex: Int = 0

    private let topAnchorID = "ItemCompactColumn.topAnchor"

    var body: some View {
        ScrollViewReader { proxy in
            let paginationEnabled = ItemCompactColumnPagination.isEnabled(
                totalCount: items.count,
                isReorderingEnabled: isReorderingEnabled
            )
            let initialLoadedCount = ItemCompactColumnPagination.initialLoadedCount(
                total: items.count,
                isEnabled: paginationEnabled
            )
            let effectiveLoadedCount = min(max(loadedItemCount, initialLoadedCount), items.count)
            let visibleItems = Array(items.prefix(effectiveLoadedCount))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .id(topAnchorID)

                    ForEach(Array(visibleItems.enumerated()), id: \.element.objectID) {
                        index, item in
                        let isDragging = dragState?.itemIDs.contains(item.objectID) ?? false

                        let row = ItemCompactRow(
                            item: item,
                            pinboards: pinboards,
                            lockedPinboardIDs: lockedPinboardIDs,
                            itemPinboardSignature: pinboardSignature(for: item),
                            isSelected: selectedItemIDs.contains(item.objectID),
                            isEditing: editingItemID == item.objectID,
                            allowPinning: allowPinning,
                            readOnly: readOnly,
                            clipItemEditor: clipItemEditor,
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
                                // During drag, toggle tapped item in/out of the drag group
                                if let state = dragState {
                                    let tappedID = tappedItem.objectID
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
                            onDoubleTap: onDoubleTap,
                            previewItemID: $previewItemID,
                            isPreviewPopoverPresented: $isPreviewPopoverPresented
                        )
                        .onAppear {
                            lastVisibleIndex = max(lastVisibleIndex, index)
                            let nextLoadedCount = ItemCompactColumnPagination.nextLoadedCount(
                                currentLoadedCount: effectiveLoadedCount,
                                visibleIndex: index,
                                totalCount: items.count,
                                isEnabled: paginationEnabled
                            )
                            if nextLoadedCount != loadedItemCount {
                                loadedItemCount = nextLoadedCount
                            }
                        }
                        .opacity(isDragging ? 0.25 : 1)
                        .background(
                            Group {
                                if isMeasuringRowFrames || dragState != nil {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ItemCompactFrameKey.self,
                                            value: [
                                                item.objectID: proxy.frame(in: .named(localCoordinateSpaceName))
                                            ]
                                        )
                                    }
                                }
                            }
                        )

                        if isDragEnabled {
                            row.simultaneousGesture(dragGesture(for: item))
                        } else {
                            row
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .onChange(of: pinboardSelectionKey) { _, _ in
                proxy.scrollTo(topAnchorID, anchor: .top)
            }
        }
        .coordinateSpace(name: scrollCoordinateSpaceName)
        .safeAreaInset(edge: .top, spacing: 0) {
            scrollTopDivider
        }
        .coordinateSpace(name: localCoordinateSpaceName)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ItemCompactColumnFrameKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
            }
        )
        .overlay(alignment: .topLeading) {
            placeholderView()
        }
        .onPreferenceChange(ItemCompactFrameKey.self) { frames in
            pendingRowFrames = frames
            guard !isRowFrameUpdateScheduled else { return }
            isRowFrameUpdateScheduled = true
            DispatchQueue.main.async {
                isRowFrameUpdateScheduled = false
                guard let latest = pendingRowFrames else { return }
                pendingRowFrames = nil
                applyItemFramesPreference(latest)
            }
        }
        .onPreferenceChange(ItemCompactColumnFrameKey.self) { frame in
            frameCoordinator.updateLatestItemRowFrame(frame)
            guard dragState == nil else { return }
            if !rectsApproximatelyEqual(frame, columnFrame) {
                columnFrame = frame
            }
        }
        .onChange(of: itemsSignature) { _, _ in
            let currentIDs = Set(rowFrames.keys)
            let newIDs = Set(items.map(\.objectID))
            if currentIDs != newIDs {
                rowFrames = [:]
                frameCoordinator.clearLatestItemFrames()
            }

            let paginationEnabled = ItemCompactColumnPagination.isEnabled(
                totalCount: items.count,
                isReorderingEnabled: isReorderingEnabled
            )
            let initialLoadedCount = ItemCompactColumnPagination.initialLoadedCount(
                total: items.count,
                isEnabled: paginationEnabled
            )
            if loadedItemCount == 0 {
                loadedItemCount = initialLoadedCount
            } else {
                loadedItemCount = min(max(loadedItemCount, initialLoadedCount), items.count)
            }
            lastVisibleIndex = min(lastVisibleIndex, max(0, items.count - 1))
        }
        .onAppear {
            let paginationEnabled = ItemCompactColumnPagination.isEnabled(
                totalCount: items.count,
                isReorderingEnabled: isReorderingEnabled
            )
            loadedItemCount = ItemCompactColumnPagination.initialLoadedCount(
                total: items.count,
                isEnabled: paginationEnabled
            )
            lastVisibleIndex = 0
        }
        .onChange(of: pinboardSelectionKey) { _, _ in
            dropTarget = nil
            pinboardDropTarget = nil
            dragState = nil
            dragOpacity = 0
            isMeasuringRowFrames = false
            rowFrames = [:]
            frameCoordinator.clearLatestItemFrames()

            let paginationEnabled = ItemCompactColumnPagination.isEnabled(
                totalCount: items.count,
                isReorderingEnabled: isReorderingEnabled
            )
            loadedItemCount = ItemCompactColumnPagination.initialLoadedCount(
                total: items.count,
                isEnabled: paginationEnabled
            )
            lastVisibleIndex = 0
        }
        .onChange(of: dragPreviewData) { newData, _ in
            if newData == nil {
                dragState = nil
            }
        }
    }

    private var itemsSignature: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.first?.objectID)
        hasher.combine(items.last?.objectID)
        return hasher.finalize()
    }

    private var scrollTopDivider: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    private func applyItemFramesPreference(_ frames: [NSManagedObjectID: CGRect]) {
        frameCoordinator.updateLatestItemFrames(frames)
        guard dragState == nil else { return }

        let countChanged = frames.count != rowFrames.count
        let keysChanged = Set(frames.keys) != Set(rowFrames.keys)
        if countChanged || keysChanged {
            rowFrames = frames
        }

        if isMeasuringRowFrames, !frames.isEmpty {
            isMeasuringRowFrames = false
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
            guard let frame = frameCoordinator.latestItemFrames[item.objectID] else {
                isMeasuringRowFrames = true
                return
            }
            rowFrames = frameCoordinator.latestItemFrames
            columnFrame = frameCoordinator.latestItemRowFrame

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
                    x: frame.origin.x + columnFrame.minX,
                    y: frame.origin.y + columnFrame.minY,
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
            // Set binding for parent state
            updateDragPreview(useCallback: false)
            // Also call callback directly to create the preview window immediately
            updateDragPreview(useCallback: true)
            // Clear snapshot after first use — SwiftUI renders on top by the next event
            dragSnapshotImage = nil
            isMeasuringRowFrames = false
        } else if var state = dragState {
            state.pointerLocation = overlayPointer
            state.translation = value.translation
            dragState = state
            updateDragPreview(useCallback: true)
        }

        let previousDropTarget = dropTarget
        let previousPinboardDropTarget = pinboardDropTarget

        if let pinboardTarget = computePinboardDropTarget(overlayLocation: overlayPointer) {
            pinboardDropTarget = pinboardTarget
            dropTarget = nil
        } else if isReorderingEnabled {
            pinboardDropTarget = nil
            let target = computeDropTarget(
                location: localPointer,
                draggedIDs: dragState?.itemIDs ?? [item.objectID]
            )
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
                    dropTarget = nil
                    pinboardDropTarget = nil
                    dragOpacity = 0
                    onPinboardDropTargetChanged?(nil)
                    self.dragState = nil
                    isMeasuringRowFrames = false
                    rowFrames = [:]
                    frameCoordinator.clearLatestItemFrames()
                    return
                }
            }
        }
    }

    private func handleDragEnded(item: ClipItem, value: DragGesture.Value) {
        if isNativeDragActive?() == true { return }

        guard isDragEnabled, let dragState, dragState.primaryItemID == item.objectID else { return }

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
                location: localPointerLocation(from: overlayPointer),
                draggedIDs: dragState.itemIDs
            )
        {
            onReorder(dragState.itemIDs, target.item, target.insertBefore)
            onReorderEnd()
            handled = true
        }

        // Check if dropped outside the overlay window (skip if native drag handled it)
        if !handled, let window, isNativeDragActive?() != true {
            let mouseLocation = NSEvent.mouseLocation
            if !window.frame.contains(mouseLocation) {
                onPasteOutside(dragState.itemIDs)
            }
        }

        endDrag(for: dragState.primaryItemID)
    }

    private func endDrag(for itemID: NSManagedObjectID) {
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
                isMeasuringRowFrames = false
                rowFrames = [:]
                frameCoordinator.clearLatestItemFrames()
            }
        }
    }

    private func computeDropTarget(location: CGPoint, draggedIDs: [NSManagedObjectID]) -> DropTarget? {
        let allOrdered = orderedFrames()
        let ordered = allOrdered.filter { !draggedIDs.contains($0.item.objectID) }

        guard !ordered.isEmpty, let first = ordered.first, let last = ordered.last else { return nil }

        let locationY = location.y
        let candidate: DropTarget?

        if locationY < first.frame.minY {
            let placeholderY = placeholderY(for: ordered, targetIndex: 0, insertBefore: true)
            candidate = DropTarget(item: first.item, insertBefore: true, placeholderY: placeholderY)
        } else if locationY > last.frame.maxY {
            let placeholderY = placeholderY(
                for: ordered,
                targetIndex: ordered.count - 1,
                insertBefore: false
            )
            candidate = DropTarget(item: last.item, insertBefore: false, placeholderY: placeholderY)
        } else if let hit = ordered.first(where: { $0.frame.minY <= locationY && locationY <= $0.frame.maxY }) {
            let insertBefore = locationY < hit.frame.midY
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == hit.item.objectID }) ?? 0
            let placeholderY = placeholderY(for: ordered, targetIndex: targetIndex, insertBefore: insertBefore)
            candidate = DropTarget(item: hit.item, insertBefore: insertBefore, placeholderY: placeholderY)
        } else if let next = ordered.first(where: { locationY < $0.frame.minY }) {
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == next.item.objectID }) ?? 0
            let placeholderY = placeholderY(for: ordered, targetIndex: targetIndex, insertBefore: true)
            candidate = DropTarget(item: next.item, insertBefore: true, placeholderY: placeholderY)
        } else {
            candidate = nil
        }

        guard let candidate else { return nil }
        let draggedFrames = draggedIDs.compactMap { rowFrames[$0] }
        guard !draggedFrames.isEmpty else { return candidate }

        let draggedMinY = draggedFrames.map(\.minY).min() ?? 0
        let draggedMaxY = draggedFrames.map(\.maxY).max() ?? 0
        let margin = rowSpacing / 2
        if candidate.placeholderY >= (draggedMinY - margin)
            && candidate.placeholderY <= (draggedMaxY + margin)
        {
            return nil
        }

        return candidate
    }

    private func placeholderY(
        for ordered: [(item: ClipItem, frame: CGRect)],
        targetIndex: Int,
        insertBefore: Bool
    ) -> CGFloat {
        if insertBefore {
            if targetIndex > 0 {
                let previous = ordered[targetIndex - 1].frame
                let current = ordered[targetIndex].frame
                return (previous.maxY + current.minY) / 2
            }
            return ordered[targetIndex].frame.minY - rowSpacing / 2
        }

        if targetIndex + 1 < ordered.count {
            let current = ordered[targetIndex].frame
            let next = ordered[targetIndex + 1].frame
            return (current.maxY + next.minY) / 2
        }

        return ordered[targetIndex].frame.maxY + rowSpacing / 2
    }

    private func computePinboardDropTarget(overlayLocation: CGPoint) -> PinboardDropTarget? {
        let capturedAllFrame = frameCoordinator.capturedAllPinboardFrame
        let capturedFrames = frameCoordinator.capturedPinboardFrames
        let capturedOffset = frameCoordinator.capturedPinboardScrollOffset
        let currentOffset = frameCoordinator.currentPinboardScrollOffset
        let scrollDelta = currentOffset - capturedOffset

        if !capturedFrames.isEmpty || capturedAllFrame != nil {
            if let capturedAllFrame {
                var adjustedFrame = capturedAllFrame
                adjustedFrame.origin.x += scrollDelta
                if adjustedFrame.contains(overlayLocation) {
                    return .all
                }
            }

            for (pinboardID, capturedFrame) in capturedFrames {
                var adjustedFrame = capturedFrame
                adjustedFrame.origin.x += scrollDelta
                if adjustedFrame.contains(overlayLocation) {
                    return .pinboard(pinboardID)
                }
            }
        } else {
            if let allPinboardFrame, allPinboardFrame.contains(overlayLocation) {
                return .all
            }
            for (pinboardID, frame) in pinboardFrames where frame.contains(overlayLocation) {
                return .pinboard(pinboardID)
            }
        }

        return nil
    }

    private func overlayPointerLocation(localPointer: CGPoint) -> CGPoint {
        if let window, let pointer = overlayPointerLocation(from: window) {
            return pointer
        }
        return CGPoint(x: localPointer.x + columnFrame.minX, y: localPointer.y + columnFrame.minY)
    }

    private func localPointerLocation(from overlayPointer: CGPoint) -> CGPoint {
        CGPoint(x: overlayPointer.x - columnFrame.minX, y: overlayPointer.y - columnFrame.minY)
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
            guard let frame = rowFrames[item.objectID] else { return nil }
            return (item: item, frame: frame)
        }
        .sorted { $0.frame.minY < $1.frame.minY }
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        if let dropTarget, let frame = rowFrames[dropTarget.item.objectID] {
            let width = max(0, frame.width - 16)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: width, height: placeholderHeight)
                .offset(x: frame.minX + 8, y: dropTarget.placeholderY - (placeholderHeight / 2))
                .transition(.opacity)
                .animation(.easeOut(duration: 0.06), value: dropTarget)
        }
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
        let previewSize: CGFloat = min(220, max(150, (window?.frame.width ?? 220) - 40))
        let previewPosition = CGPoint(
            x: dragState.baseCenter.x + dragState.translation.width + columnFrame.minX,
            y: dragState.baseCenter.y + dragState.translation.height + columnFrame.minY
        )

        let data = DragPreviewData(
            items: draggedItems,
            pinboards: pinboards,
            cardSize: previewSize,
            position: previewPosition,
            opacity: dragOpacity,
            isCompactLayout: true,
            snapshotImage: dragSnapshotImage
        )

        if useCallback, let callback = onPreviewUpdate {
            callback(data)
        } else {
            dragPreviewData = data
        }
    }
}

private struct ItemCompactFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] { [:] }

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ItemCompactColumnFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct DropTarget: Equatable {
    let item: ClipItem
    let insertBefore: Bool
    let placeholderY: CGFloat

    static func == (lhs: DropTarget, rhs: DropTarget) -> Bool {
        lhs.item.objectID == rhs.item.objectID
            && lhs.insertBefore == rhs.insertBefore
            && lhs.placeholderY == rhs.placeholderY
    }
}

struct ItemCompactColumnPagination {
    static let thresholdCount: Int = 120
    static let batchSize: Int = 80
    static let preloadBuffer: Int = 20

    static func isEnabled(totalCount: Int, isReorderingEnabled: Bool) -> Bool {
        totalCount > thresholdCount && !isReorderingEnabled
    }

    static func initialLoadedCount(total: Int, isEnabled: Bool) -> Int {
        guard isEnabled else { return total }
        return min(batchSize, total)
    }

    static func nextLoadedCount(
        currentLoadedCount: Int,
        visibleIndex: Int,
        totalCount: Int,
        isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return totalCount }
        let preloadStartIndex = max(0, currentLoadedCount - preloadBuffer)
        guard visibleIndex >= preloadStartIndex else { return currentLoadedCount }
        return min(currentLoadedCount + batchSize, totalCount)
    }
}
