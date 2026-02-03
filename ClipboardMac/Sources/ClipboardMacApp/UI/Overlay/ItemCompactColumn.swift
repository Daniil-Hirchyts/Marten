import AppKit
import ClipboardCore
import ClipboardMacServices
import CoreData
import SwiftUI

struct ItemCompactColumn: View {
    private let rowSpacing: CGFloat = 8
    private let placeholderHeight: CGFloat = 3
    private let localCoordinateSpaceName = "ItemCompactColumnLocalSpace"
    private let scrollCoordinateSpaceName = "ItemCompactColumnScrollSpace"

    let items: [ClipItem]
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let selectedItemIDs: Set<NSManagedObjectID>
    let editingItemID: NSManagedObjectID?
    let allowPinning: Bool
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
    @State private var pendingRowFrames: [NSManagedObjectID: CGRect]?
    @State private var isRowFrameUpdateScheduled = false
    @State private var scrollContentOffset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(items, id: \.objectID) { item in
                    let isDragging = dragState?.itemIDs.contains(item.objectID) ?? false

                    let row = ItemCompactRow(
                        item: item,
                        pinboards: pinboards,
                        lockedPinboardIDs: lockedPinboardIDs,
                        isSelected: selectedItemIDs.contains(item.objectID),
                        isEditing: editingItemID == item.objectID,
                        allowPinning: allowPinning,
                        clipItemEditor: clipItemEditor,
                        onPaste: { onPaste(item) },
                        onPastePlainText: { onPastePlainText(item) },
                        onCopy: { onCopy(item) },
                        onDelete: { onDelete(item) },
                        onTogglePin: { onTogglePin(item) },
                        onMoveToPinboard: { onMoveToPinboard(item, $0) },
                        onCreatePinboard: { onCreatePinboard(item) },
                        onEdit: { onEdit(item) },
                        onRename: { onRename(item) },
                        onCommitRename: { onCommitRename(item, $0) },
                        onTap: { onTap(item) },
                        onDoubleTap: { onDoubleTap(item) },
                        previewItemID: $previewItemID,
                        isPreviewPopoverPresented: $isPreviewPopoverPresented
                    )
                    .opacity(isDragging ? 0.25 : 1)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ItemCompactFrameKey.self,
                                value: [item.objectID: proxy.frame(in: .named(localCoordinateSpaceName))]
                            )
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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItemCompactScrollOffsetKey.self,
                        value: proxy.frame(in: .named(scrollCoordinateSpaceName)).minY
                    )
                }
            )
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
        .onPreferenceChange(ItemCompactScrollOffsetKey.self) { offset in
            let normalizedOffset = abs(offset) < 0.5 ? 0 : offset
            if abs(normalizedOffset - scrollContentOffset) > 0.5 {
                scrollContentOffset = normalizedOffset
            }
        }
        .onChange(of: items.map(\.objectID)) { _, _ in
            let currentIDs = Set(rowFrames.keys)
            let newIDs = Set(items.map(\.objectID))
            if currentIDs != newIDs {
                rowFrames = [:]
                frameCoordinator.clearLatestItemFrames()
            }
        }
        .onChange(of: dragPreviewData) { newData, _ in
            if newData == nil {
                dragState = nil
            }
        }
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

        if let dragState, !dragState.itemIDs.contains(item.objectID) {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )
        let overlayPointer = overlayPointerLocation(localPointer: localPointer)

        if dragState == nil {
            guard let frame = frameCoordinator.latestItemFrames[item.objectID] else { return }
            rowFrames = frameCoordinator.latestItemFrames
            columnFrame = frameCoordinator.latestItemRowFrame

            let draggedID = item.objectID
            let itemIDs: [NSManagedObjectID]
            if selectedItemIDs.contains(draggedID) {
                itemIDs = orderedObjectIDs(for: selectedItemIDs)
            } else {
                itemIDs = [draggedID]
            }

            dragState = DragState(
                itemIDs: itemIDs,
                primaryItemID: draggedID,
                pointerLocation: overlayPointer,
                baseCenter: CGPoint(x: frame.midX, y: frame.midY),
                translation: .zero
            )
            dragOpacity = 1
            updateDragPreview(useCallback: false)
        } else if var state = dragState {
            state.pointerLocation = overlayPointer
            state.translation = value.translation
            dragState = state
            updateDragPreview(useCallback: true)
        }

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
    }

    private func handleDragEnded(item: ClipItem, value: DragGesture.Value) {
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

        if !handled, let window {
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
        updateDragPreview(useCallback: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if dragState?.primaryItemID == itemID {
                dragState = nil
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
            isCompactLayout: true
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

private struct ItemCompactScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DragState {
    let itemIDs: [NSManagedObjectID]
    let primaryItemID: NSManagedObjectID
    var pointerLocation: CGPoint
    let baseCenter: CGPoint
    var translation: CGSize
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

private enum PinboardDropTarget: Equatable {
    case all
    case pinboard(NSManagedObjectID)
}
