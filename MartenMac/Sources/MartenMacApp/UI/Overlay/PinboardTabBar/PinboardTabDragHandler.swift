import AppKit
import MartenCore
import SwiftUI

extension PinboardTabBar {
    func dragGesture(for pinboard: Pinboard, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(localCoordinateSpaceName))
            .onChanged { value in
                handleDragChanged(pinboard: pinboard, value: value)
            }
            .onEnded { value in
                handleDragEnded(pinboard: pinboard, value: value)
            }
    }

    func handleDragChanged(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder else { return }

        if let dragState, dragState.itemID != pinboard.objectID {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )

        let previousDropTarget = dropTarget

        if dragState == nil {
            guard let localFrame = frameManager.latestTabFrames[pinboard.objectID] else {
                return
            }

            guard !frameManager.latestTabFrames.isEmpty else {
                return
            }

            let handler = PinboardDragHandler(pinboards: pinboards, tabSpacing: tabSpacing)
            guard
                let result = handler.beginDrag(
                    pinboard: pinboard,
                    at: localPointer,
                    localFrame: localFrame,
                    tabFrames: frameManager.latestTabFrames
                )
            else {
                return
            }

            dragState = result.dragState
            frameManager.setCachedOrderedFrames(result.cachedOrderedFrames)
            dragOpacity = 1

            updatePreviewData(for: pinboard, localFrame: localFrame)

            if let cachedLocal = frameManager.cachedOrderedFrames {
                dropTarget = handler.computeDropTarget(
                    location: localPointer,
                    draggedID: pinboard.objectID,
                    orderedFrames: cachedLocal,
                    visibleBounds: scrollViewBounds
                )
            }
        } else {
            guard let currentDragState = dragState,
                let cachedLocal = frameManager.cachedOrderedFrames
            else { return }
            let handler = PinboardDragHandler(pinboards: pinboards, tabSpacing: tabSpacing)
            let result = handler.updateDrag(
                currentState: currentDragState,
                translation: value.translation,
                newLocation: localPointer,
                cachedLocalOrderedFrames: cachedLocal,
                visibleBounds: scrollViewBounds
            )

            dragState = result.dragState
            dropTarget = result.dropTarget

            if let localFrame = frameManager.latestTabFrames[pinboard.objectID] {
                updatePreviewData(for: pinboard, localFrame: localFrame)
            }

            if let scrollProxy = currentScrollProxy {
                checkAutoScroll(at: localPointer, scrollProxy: scrollProxy)
            }
        }

        if dropTarget != previousDropTarget && dropTarget != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    func handleDragEnded(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder,
            let dragState,
            dragState.itemID == pinboard.objectID,
            let cachedLocal = frameManager.cachedOrderedFrames
        else {
            return
        }

        let handler = PinboardDragHandler(pinboards: pinboards, tabSpacing: tabSpacing)
        if let result = handler.endDrag(
            state: dragState,
            cachedLocalOrderedFrames: cachedLocal,
            visibleBounds: scrollViewBounds
        ) {
            onReorder(result.draggedItem, result.targetItem, result.insertBefore)
            onReorderEnd()
        }

        endDrag(for: dragState.itemID)
    }

    func endDrag(for itemID: NSManagedObjectID) {
        stopAutoScroll()
        onPreviewUpdate?(nil)

        withAnimation(.easeOut(duration: 0.1)) {
            dropTarget = nil
            dragOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if dragState?.itemID == itemID {
                dragState = nil
                frameManager.clearCaches()
            }
        }
    }

    func updatePreviewData(for pinboard: Pinboard, localFrame: CGRect) {
        let data = PinboardDragPreviewData(
            title: pinboard.name,
            colorHex: pinboard.colorHex,
            iconName: pinboard.iconName,
            size: localFrame.size,
            opacity: dragOpacity
        )
        onPreviewUpdate?(data)
    }

    func handleAutoScrollStateChange(_ newState: PinboardTabDragState?, scrollProxy: ScrollViewProxy) {
        if newState == nil {
            stopAutoScroll()
        }
    }

    func startAutoScroll(direction: AutoScrollDirection, scrollProxy: ScrollViewProxy) {
        stopAutoScroll()

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [self] _ in
            guard let dragState = dragState else {
                stopAutoScroll()
                return
            }

            let sortedPinboards = pinboards.sorted { lhs, rhs in
                let lhsFrame = frameManager.latestTabFrames[lhs.objectID] ?? .zero
                let rhsFrame = frameManager.latestTabFrames[rhs.objectID] ?? .zero
                return lhsFrame.minX < rhsFrame.minX
            }

            guard !sortedPinboards.isEmpty else { return }

            let currentX = dragState.pointerLocation.x

            switch direction {
            case .leading:
                if let targetPinboard = sortedPinboards.last(where: {
                    guard let frame = frameManager.latestTabFrames[$0.objectID] else {
                        return false
                    }
                    return frame.minX < currentX - autoScrollEdgeInset
                }) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(targetPinboard.id, anchor: .leading)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo("all", anchor: .leading)
                    }
                }
            case .trailing:
                if let targetPinboard = sortedPinboards.first(where: {
                    guard let frame = frameManager.latestTabFrames[$0.objectID] else {
                        return false
                    }
                    return frame.maxX > currentX + autoScrollEdgeInset
                }) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(targetPinboard.id, anchor: .trailing)
                    }
                }
            }
        }
    }

    func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    func checkAutoScroll(at location: CGPoint, scrollProxy: ScrollViewProxy) {
        guard dragState != nil, !scrollViewBounds.isEmpty else {
            stopAutoScroll()
            return
        }

        let relativeX = location.x - scrollViewBounds.minX

        if relativeX < autoScrollEdgeInset {
            if autoScrollTimer == nil {
                startAutoScroll(direction: .leading, scrollProxy: scrollProxy)
            }
        } else if relativeX > scrollViewBounds.width - autoScrollEdgeInset {
            if autoScrollTimer == nil {
                startAutoScroll(direction: .trailing, scrollProxy: scrollProxy)
            }
        } else {
            stopAutoScroll()
        }
    }

    enum AutoScrollDirection {
        case leading
        case trailing
    }
}

struct PinboardTabPreview: View {
    let title: String
    let colorHex: String?
    let iconName: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            if let colorHex {
                PinboardIndicator(colorHex: colorHex, sign: iconName, size: 16)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 20)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            Group {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                } else {
                    (colorScheme == .dark ? Color.white : Color.black).opacity(DesignTokens.Opacity.backgroundStrong)
                }
            }
        )
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}
