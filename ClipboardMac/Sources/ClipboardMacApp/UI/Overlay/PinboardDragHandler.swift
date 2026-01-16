import ClipboardCore
import ClipboardMacServices
import CoreData
import OSLog
import SwiftUI

/// Result from beginning a drag operation
struct DragBeginResult {
    let dragState: PinboardTabDragState
    let cachedOrderedFrames: [(item: Pinboard, frame: CGRect)]
}

/// Result from updating a drag operation
struct DragUpdateResult {
    let dragState: PinboardTabDragState
    let dropTarget: PinboardTabDropTarget?
}

/// Result from ending a drag operation
struct DragEndResult {
    let draggedItem: Pinboard
    let targetItem: Pinboard
    let insertBefore: Bool
}

/// Handles all drag-and-drop logic for pinboard tab reordering
struct PinboardDragHandler {
    let pinboards: [Pinboard]
    let tabSpacing: CGFloat

    // MARK: - Drag Lifecycle

    /// Begins a drag operation for the specified pinboard
    func beginDrag(
        pinboard: Pinboard,
        at location: CGPoint,
        localFrame: CGRect,
        tabFrames: [NSManagedObjectID: CGRect]
    ) -> DragBeginResult? {
        // Calculate cursor offset from item center
        let cursorOffset = CGSize(
            width: location.x - localFrame.midX,
            height: location.y - localFrame.midY
        )

        let cachedOrderedFrames = computeOrderedFrames(from: tabFrames)

        Logger.drag.debug("Drag started: item=\(pinboard.name)")

        let dragState = PinboardTabDragState(
            itemID: pinboard.objectID,
            pointerLocation: location,
            localBaseCenter: CGPoint(x: localFrame.midX, y: localFrame.midY),
            translation: .zero,
            cursorOffset: cursorOffset
        )

        return DragBeginResult(
            dragState: dragState,
            cachedOrderedFrames: cachedOrderedFrames
        )
    }

    /// Updates a drag operation with new position
    func updateDrag(
        currentState: PinboardTabDragState,
        translation: CGSize,
        newLocation: CGPoint,
        cachedLocalOrderedFrames: [(item: Pinboard, frame: CGRect)]
    ) -> DragUpdateResult {
        var updatedState = currentState
        updatedState.pointerLocation = newLocation
        updatedState.translation = translation

        let target = computeDropTarget(
            location: newLocation,
            draggedID: currentState.itemID,
            orderedFrames: cachedLocalOrderedFrames
        )

        return DragUpdateResult(dragState: updatedState, dropTarget: target)
    }

    /// Ends a drag operation and returns the reorder action if valid
    func endDrag(
        state: PinboardTabDragState,
        cachedLocalOrderedFrames: [(item: Pinboard, frame: CGRect)]
    ) -> DragEndResult? {
        Logger.drag.debug("Drag ended")

        guard
            let target = computeDropTarget(
                location: state.pointerLocation,
                draggedID: state.itemID,
                orderedFrames: cachedLocalOrderedFrames
            ),
            let draggedItem = pinboards.first(where: { $0.objectID == state.itemID })
        else {
            return nil
        }

        Logger.drag.debug(
            "Reorder: \(draggedItem.name) -> \(target.item.name), insertBefore=\(target.insertBefore)"
        )

        return DragEndResult(
            draggedItem: draggedItem,
            targetItem: target.item,
            insertBefore: target.insertBefore
        )
    }

    // MARK: - Drop Target Computation

    /// Computes drop target using local-space frames (stable during drag)
    func computeDropTarget(
        location: CGPoint,
        draggedID: NSManagedObjectID,
        orderedFrames: [(item: Pinboard, frame: CGRect)]
    ) -> PinboardTabDropTarget? {
        guard let draggedIndex = orderedFrames.firstIndex(where: { $0.item.objectID == draggedID }),
            let first = orderedFrames.first,
            let last = orderedFrames.last
        else {
            return nil
        }

        let locationX = location.x
        let candidate: PinboardTabDropTarget?

        if locationX < first.frame.minX {
            let pX = computePlaceholderX(for: orderedFrames, targetIndex: 0, insertBefore: true)
            candidate = PinboardTabDropTarget(
                item: first.item, insertBefore: true, placeholderX: pX)
        } else if locationX > last.frame.maxX {
            let pX = computePlaceholderX(
                for: orderedFrames, targetIndex: orderedFrames.count - 1, insertBefore: false)
            candidate = PinboardTabDropTarget(
                item: last.item, insertBefore: false, placeholderX: pX)
        } else if let hit = orderedFrames.first(where: {
            $0.frame.minX <= locationX && locationX <= $0.frame.maxX
        }) {
            let insertBefore = locationX < hit.frame.midX
            let targetIndex =
                orderedFrames.firstIndex(where: { $0.item.objectID == hit.item.objectID }) ?? 0
            let pX = computePlaceholderX(
                for: orderedFrames, targetIndex: targetIndex, insertBefore: insertBefore)
            candidate = PinboardTabDropTarget(
                item: hit.item, insertBefore: insertBefore, placeholderX: pX)
        } else if let next = orderedFrames.first(where: { locationX < $0.frame.minX }) {
            let targetIndex =
                orderedFrames.firstIndex(where: { $0.item.objectID == next.item.objectID }) ?? 0
            let pX = computePlaceholderX(
                for: orderedFrames, targetIndex: targetIndex, insertBefore: true)
            candidate = PinboardTabDropTarget(item: next.item, insertBefore: true, placeholderX: pX)
        } else {
            candidate = nil
        }

        guard let candidate,
            let targetIndex = orderedFrames.firstIndex(where: {
                $0.item.objectID == candidate.item.objectID
            }),
            !isNoOp(
                draggedIndex: draggedIndex, targetIndex: targetIndex,
                insertBefore: candidate.insertBefore)
        else {
            return nil
        }

        return candidate
    }

    /// Calculates placeholder X position in local-space
    private func computePlaceholderX(
        for ordered: [(item: Pinboard, frame: CGRect)],
        targetIndex: Int,
        insertBefore: Bool
    ) -> CGFloat {
        if insertBefore {
            if targetIndex > 0 {
                let previous = ordered[targetIndex - 1].frame
                let current = ordered[targetIndex].frame
                return (previous.maxX + current.minX) / 2
            }
            return ordered[targetIndex].frame.minX - tabSpacing / 2
        }

        if targetIndex + 1 < ordered.count {
            let current = ordered[targetIndex].frame
            let next = ordered[targetIndex + 1].frame
            return (current.maxX + next.minX) / 2
        }

        return ordered[targetIndex].frame.maxX + tabSpacing / 2
    }

    /// Checks if a reorder operation would be a no-op
    private func isNoOp(draggedIndex: Int, targetIndex: Int, insertBefore: Bool) -> Bool {
        if draggedIndex == targetIndex {
            return true
        }
        if insertBefore && targetIndex == draggedIndex + 1 {
            return true
        }
        if !insertBefore && targetIndex == draggedIndex - 1 {
            return true
        }
        return false
    }

    // MARK: - Frame Ordering

    /// Computes ordered frames from content-space
    private func computeOrderedFrames(from tabFrames: [NSManagedObjectID: CGRect]) -> [(
        item: Pinboard, frame: CGRect
    )] {
        pinboards.compactMap { pinboard in
            guard let frame = tabFrames[pinboard.objectID] else { return nil }
            return (item: pinboard, frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }
}

// MARK: - Supporting Types

struct PinboardTabDragState: Equatable {
    let itemID: NSManagedObjectID
    var pointerLocation: CGPoint
    // Local-space center for stable drag preview positioning
    let localBaseCenter: CGPoint
    var translation: CGSize
    // Offset from cursor to item center at drag start
    let cursorOffset: CGSize

    static func == (lhs: PinboardTabDragState, rhs: PinboardTabDragState) -> Bool {
        lhs.itemID == rhs.itemID && lhs.pointerLocation == rhs.pointerLocation
            && lhs.translation == rhs.translation
    }
}

struct PinboardTabDropTarget: Equatable {
    let item: Pinboard
    let insertBefore: Bool
    let placeholderX: CGFloat

    static func == (lhs: PinboardTabDropTarget, rhs: PinboardTabDropTarget) -> Bool {
        lhs.item.objectID == rhs.item.objectID && lhs.insertBefore == rhs.insertBefore
            && lhs.placeholderX == rhs.placeholderX
    }
}
