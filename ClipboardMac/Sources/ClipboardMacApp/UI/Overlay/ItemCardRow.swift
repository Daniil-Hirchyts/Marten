import AppKit
import ClipboardCore
import CoreData
import SwiftUI

struct ItemCardRow: View {
    private let cardSpacing: CGFloat = 12
    private let placeholderWidth: CGFloat = 3
    private let localCoordinateSpaceName = "ItemRowLocalSpace"

    let items: [ClipItem]
    let pinboards: [Pinboard]
    let mode: OverlayMode
    let selectedItemIDs: Set<NSManagedObjectID>
    let editingItemID: NSManagedObjectID?
    let allowPinning: Bool
    let isDragEnabled: Bool
    let isReorderingEnabled: Bool
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
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

    @State private var itemFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var rowFrame: CGRect = .zero
    @State private var dragState: DragState?
    @State private var dragOpacity: Double = 0
    @State private var dragCenteringOffset: CGSize = .zero
    @State private var centeringTimer: Timer?
    @State private var dropTarget: DropTarget?
    @State private var pinboardDropTarget: PinboardDropTarget?

    var body: some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.height
            // Add side margin (14) to the placeholder allowance so cards start aligned with header
            let sideMargin: CGFloat = 14
            let placeholderInset = sideMargin + (placeholderWidth / 2)

            if #available(macOS 14.0, *) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        LazyHStack(alignment: .top, spacing: cardSpacing) {
                            cardViews(size: cardSize, proxy: proxy)
                        }
                        .scrollTargetLayout()
                    }
                }
                .contentMargins(.horizontal, placeholderInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        LazyHStack(alignment: .top, spacing: cardSpacing) {
                            cardViews(size: cardSize, proxy: proxy)
                        }
                        .padding(.horizontal, placeholderInset)
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
            itemFrames = frames
        }
        .onPreferenceChange(ItemRowFrameKey.self) { frame in
            rowFrame = frame
        }
        .onChange(of: dragState?.primaryItemID) { _ in updateDragPreview() }
        .onChange(of: dragState?.translation) { _ in updateDragPreview() }
        .onChange(of: dragOpacity) { _ in updateDragPreview() }
        .onChange(of: dragCenteringOffset) { _ in updateDragPreview() }
    }

    @ViewBuilder
    private func cardViews(size: CGFloat, proxy: ScrollViewProxy?) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.objectID) { index, item in
            let isDragging = dragState?.itemIDs.contains(item.objectID) ?? false

            let base = ItemCard(
                item: item,
                pinboards: pinboards,
                isSelected: selectedItemIDs.contains(item.objectID),
                isEditing: editingItemID == item.objectID,
                badgeIndex: badgeIndex(for: index),
                isDropTarget: false,
                showPinIndicator: allowPinning,
                allowPinning: allowPinning,
                onPaste: { onPaste(item) },
                onPastePlainText: { onPastePlainText(item) },
                onCopy: { onCopy(item) },
                onDelete: { onDelete(item) },
                onTogglePin: { onTogglePin(item) },
                onMoveToPinboard: { onMoveToPinboard(item, $0) },
                onCreatePinboard: { onCreatePinboard(item) },
                onRename: { onRename(item) },
                onCommitRename: { newTitle in onCommitRename(item, newTitle) },
                onTap: {
                    withAnimation {
                        proxy?.scrollTo(item.objectID)
                    }
                    onTap(item)
                },
                onDoubleTap: { onDoubleTap(item) }
            )
            .id(item.objectID)
            .frame(width: size, height: size)
            .opacity(isDragging ? 0.25 : 1)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItemFrameKey.self,
                        value: [item.objectID: proxy.frame(in: .named(localCoordinateSpaceName))]
                    )
                }
            )

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

        if let dragState, !dragState.itemIDs.contains(item.objectID) {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )
        let overlayPointer = overlayPointerLocation(localPointer: localPointer)

        if dragState == nil {
            guard let frame = itemFrames[item.objectID] else { return }

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
            
            // Calculate initial offset from center to cursor
            let centerX = frame.midX
            let centerY = frame.midY
            // pointer starts at value.startLocation
            let startPointerX = value.startLocation.x
            let startPointerY = value.startLocation.y
            
            // If pointer is at (10, 10) and center is (50, 50)
            // We want preview to be at (50, 50) initially.
            // Pointer is at (10, 10).
            // Normal logic puts preview at center + translation.
            // translation is 0. preview is at center (50, 50).
            // But visually, mouse is at 10,10.
            // We want card to be under mouse if offset logic wasn't applied?
            // Actually, existing logic puts card at its ORIGINAL center.
            // If mouse is at corner, card is offset from mouse.
            // We want card to MOVE to be centered on mouse.
            // Target center relative to mouse: Mouse + 0.
            // Current center relative to mouse: Mouse + (Center - Mouse).
            // So offset = Center - Mouse.
            // We want to animate offset -> 0.
            // But we actually apply this offset to the position?
            
            // Let's look at updateDragPreview:
            // pos = baseCenter + translation.
            // translation = mouse - startMouse.
            // pos = baseCenter + mouse - startMouse.
            // If mouse == startMouse (start), pos = baseCenter.
            
            // We want pos to start at baseCenter, and animate to (startMouse + translation) = mouse.
            // At start: pos = baseCenter. mouse = startMouse.
            // Difference = baseCenter - startMouse.
            // We want to animate FROM this difference TO zero?
            // No, we want pos to equal mouse eventually.
            // Currently pos = baseCenter + (mouse - startMouse).
            // We want pos = mouse.
            // Discrepancy = (baseCenter + mouse - startMouse) - mouse = baseCenter - startMouse.
            // So there is a constant offset of (baseCenter - startMouse).
            // We want to remove this offset over time.
            
            // So we start with offset = 0 (relative to logic), which means visual offset exists.
            // We want to add a correction vector C.
            // Final position = StandardLogicPosition - C.
            // Initially, we want StandardLogicPosition - C = StandardLogicPosition. -> C=0.
            // Wait, initially we are fine (card under finger).
            // We want card center to move to finger.
            // Center is at baseCenter. Finger is at startMouse.
            // We want Center -> Finger.
            // So we want to add (Finger - Center) to position over time.
            // Let targetCorrection = startMouse - baseCenter.
            // We start at correction = 0. We animate correction to targetCorrection.
            
            dragCenteringOffset = CGSize(
                width: startPointerX - centerX,
                height: startPointerY - centerY
            )
            
            // Manual animation loop for smooth window updates
            centeringTimer?.invalidate()
            centeringTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                let easing: CGFloat = 0.2
                let current = dragCenteringOffset
                let nextX = current.width * (1 - easing)
                let nextY = current.height * (1 - easing)
                
                if abs(nextX) < 0.5 && abs(nextY) < 0.5 {
                    dragCenteringOffset = .zero
                    timer.invalidate()
                    centeringTimer = nil
                } else {
                    dragCenteringOffset = CGSize(width: nextX, height: nextY)
                }
            }
            
        } else if var state = dragState {
            state.pointerLocation = overlayPointer
            state.translation = value.translation
            dragState = state
        }

        if let pinboardTarget = computePinboardDropTarget(overlayLocation: overlayPointer) {
            withAnimation(.easeOut(duration: 0.06)) {
                pinboardDropTarget = pinboardTarget
                dropTarget = nil
            }
        } else if isReorderingEnabled {
            pinboardDropTarget = nil
            let target = computeDropTarget(location: localPointer, draggedIDs: dragState?.itemIDs ?? [item.objectID])
            withAnimation(.easeOut(duration: 0.06)) {
                dropTarget = target
            }
        } else {
            withAnimation(.easeOut(duration: 0.06)) {
                dropTarget = nil
            }
        }
    }

    private func handleDragEnded(item: ClipItem, value: DragGesture.Value) {
        guard isDragEnabled,
              let dragState,
              dragState.primaryItemID == item.objectID else {
            return
        }

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
                  let target = computeDropTarget(location: localPointerLocation(from: overlayPointer), draggedIDs: dragState.itemIDs) {
            onReorder(dragState.itemIDs, target.item, target.insertBefore)
            onReorderEnd()
            handled = true
        }

        // Check if dropped outside the overlay window
        if !handled, let window = window {
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
        withAnimation(.easeOut(duration: 0.06)) {
            dropTarget = nil
            pinboardDropTarget = nil
            dragOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if dragState?.primaryItemID == itemID {
                dragState = nil
            }
        }
    }

    private func computeDropTarget(location: CGPoint, draggedIDs: [NSManagedObjectID]) -> DropTarget? {
        let allOrdered = orderedFrames()
        let ordered = allOrdered.filter { frame in
            !draggedIDs.contains(frame.item.objectID)
        }

        guard !ordered.isEmpty,
              let first = ordered.first,
              let last = ordered.last else {
            return nil
        }

        let locationX = location.x
        let candidate: DropTarget?

        if locationX < first.frame.minX {
            let placeholderX = placeholderX(for: ordered, targetIndex: 0, insertBefore: true)
            candidate = DropTarget(item: first.item, insertBefore: true, placeholderX: placeholderX)
        } else if locationX > last.frame.maxX {
            let placeholderX = placeholderX(for: ordered, targetIndex: ordered.count - 1, insertBefore: false)
            candidate = DropTarget(item: last.item, insertBefore: false, placeholderX: placeholderX)
        } else if let hit = ordered.first(where: { $0.frame.minX <= locationX && locationX <= $0.frame.maxX }) {
            let insertBefore = locationX < hit.frame.midX
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == hit.item.objectID }) ?? 0
            let placeholderX = placeholderX(for: ordered, targetIndex: targetIndex, insertBefore: insertBefore)
            candidate = DropTarget(item: hit.item, insertBefore: insertBefore, placeholderX: placeholderX)
        } else if let next = ordered.first(where: { locationX < $0.frame.minX }) {
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == next.item.objectID }) ?? 0
            let placeholderX = placeholderX(for: ordered, targetIndex: targetIndex, insertBefore: true)
            candidate = DropTarget(item: next.item, insertBefore: true, placeholderX: placeholderX)
        } else {
            candidate = nil
        }

        return candidate
    }

    private func placeholderX(for ordered: [(item: ClipItem, frame: CGRect)], targetIndex: Int, insertBefore: Bool) -> CGFloat {
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
        if let allPinboardFrame, allPinboardFrame.contains(overlayLocation) {
            return .all
        }

        for (pinboardID, frame) in pinboardFrames {
            if frame.contains(overlayLocation) {
                return .pinboard(pinboardID)
            }
        }

        return nil
    }

    private func overlayPointerLocation(localPointer: CGPoint) -> CGPoint {
        if let window, let pointer = overlayPointerLocation(from: window) {
            return pointer
        }
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
                .fill(Color.white.opacity(0.5))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 8)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.06), value: dropTarget)
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

    private func updateDragPreview() {
        guard let dragState else {
            dragPreviewData = nil
            return
        }

        let draggedItems = dragState.itemIDs.compactMap { id in
            items.first { $0.objectID == id }
        }
        let cardSize = itemFrames[dragState.primaryItemID]?.width ?? 0

        let previewPosition = CGPoint(
            x: dragState.baseCenter.x + dragState.translation.width + rowFrame.minX + dragCenteringOffset.width,
            y: dragState.baseCenter.y + dragState.translation.height + rowFrame.minY + dragCenteringOffset.height
        )

        dragPreviewData = DragPreviewData(
            items: draggedItems,
            pinboards: pinboards,
            cardSize: cardSize,
            position: previewPosition,
            opacity: dragOpacity
        )
    }
}

private struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] = [:]

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ItemRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct DragPreviewData: Equatable {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let cardSize: CGFloat
    let position: CGPoint
    let opacity: Double

    static func == (lhs: DragPreviewData, rhs: DragPreviewData) -> Bool {
        lhs.items.map { $0.objectID } == rhs.items.map { $0.objectID } &&
        lhs.pinboards.map { $0.objectID } == rhs.pinboards.map { $0.objectID } &&
        lhs.cardSize == rhs.cardSize &&
        lhs.position == rhs.position &&
        lhs.opacity == rhs.opacity
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
    let placeholderX: CGFloat

    static func == (lhs: DropTarget, rhs: DropTarget) -> Bool {
        lhs.item.objectID == rhs.item.objectID &&
            lhs.insertBefore == rhs.insertBefore &&
            lhs.placeholderX == rhs.placeholderX
    }
}

private enum PinboardDropTarget: Equatable {
    case all
    case pinboard(NSManagedObjectID)
}

struct ItemCardDragPreview: View {
    let item: ClipItem
    let pinboards: [Pinboard]

    var body: some View {
        ItemCard(
            item: item,
            pinboards: pinboards,
            isSelected: false,
            isEditing: false,
            badgeIndex: nil,
            isDropTarget: false,
            showPinIndicator: false,
            allowPinning: false,
            onPaste: {},
            onPastePlainText: {},
            onCopy: {},
            onDelete: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onCreatePinboard: {},
            onRename: {},
            onCommitRename: { _ in },
            onTap: {},
            onDoubleTap: {}
        )
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}

struct MultiItemCardDragPreview: View {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let cardSize: CGFloat

    private let stackOffset: CGFloat = 4
    private let maxVisibleCards = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.prefix(maxVisibleCards).enumerated()), id: \.offset) { index, item in
                ItemCard(
                    item: item,
                    pinboards: pinboards,
                    isSelected: false,
                    isEditing: false,
                    badgeIndex: nil,
                    isDropTarget: false,
                    showPinIndicator: false,
                    allowPinning: false,
                    onPaste: {},
                    onPastePlainText: {},
                    onCopy: {},
                    onDelete: {},
                    onTogglePin: {},
                    onMoveToPinboard: { _ in },
                    onCreatePinboard: {},
                    onRename: {},
                    onCommitRename: { _ in },
                    onTap: {},
                    onDoubleTap: {}
                )
                .frame(width: cardSize, height: cardSize)
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
    }
}
