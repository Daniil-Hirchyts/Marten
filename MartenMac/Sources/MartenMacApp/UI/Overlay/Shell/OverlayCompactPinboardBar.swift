import CoreData
import MartenCore
import SwiftUI

private let compactBarCoordinateSpaceName = "CompactBarLocalSpace"

extension OverlayShellView {
    var compactPinboardBar: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    compactAllItemsPill
                        .id("all")
                    ForEach(Array(visiblePinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                        compactPinboardPill(for: pinboard, index: index)
                            .id(pinboard.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .coordinateSpace(name: compactBarCoordinateSpaceName)
            .scrollClipDisabled()
            .frame(height: 44)
            .overlay(alignment: .topLeading) {
                compactPlaceholderView()
            }
            .overlay(alignment: .topLeading) {
                compactDragPreviewView()
            }
            .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
                handlePinboardLayoutChange(layout)
                // Also track pill frames for drag-reorder
                if !layout.tabFrames.isEmpty {
                    for (id, frame) in layout.tabFrames {
                        compactPillFrames[id] = frame
                    }
                }
            }
            .popover(isPresented: $verticalPinboardCreateState.isPresented, arrowEdge: .bottom) {
                verticalPinboardCreatePopover
            }
            .popover(isPresented: $verticalPinboardEditState.isPresented, arrowEdge: .bottom) {
                verticalPinboardEditPopover
            }
            .onChange(of: searchModel.selectedPinboardID) { _, newValue in
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        if let newValue {
                            scrollProxy.scrollTo(newValue, anchor: .center)
                        } else {
                            scrollProxy.scrollTo("all", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - All Items Pill

    private var compactAllItemsPill: some View {
        let isSelected = searchModel.selectedPinboardID == nil
        let isDropTarget = itemDragPinboardDropTargetID == PinboardTabBarIDs.allTabObjectID
        let pillSize: CGFloat = 28
        return Button {
            handlePinboardSelect(nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tray")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if isSelected {
                    Text("All Items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isSelected ? 10 : 0)
            .frame(width: isSelected ? nil : pillSize, height: pillSize)
            .background { compactPillBackground(isSelected: isSelected || isDropTarget) }
        }
        .buttonStyle(.plain)
        .contentShape(isSelected ? AnyShape(Capsule()) : AnyShape(Circle()))
        .background(compactPillFrameReporter(objectID: PinboardTabBarIDs.allTabObjectID, isAll: true))
        .contextMenu {
            Button {
                beginPinboardCreate(for: nil)
            } label: {
                Label("New Pinboard…", systemImage: "plus")
            }
        }
        .accessibilityIdentifier("overlay.compactPinboard.all")
    }

    // MARK: - Pinboard Pill

    private func compactPinboardPill(for pinboard: Pinboard, index: Int) -> some View {
        let isSelected = searchModel.selectedPinboardID == pinboard.id
        let locked = pinboardLockController.isLocked(pinboardID: pinboard.id)
        let unlocked = pinboardLockController.canAccess(pinboardID: pinboard.id)
        let isDropTarget = itemDragPinboardDropTargetID == pinboard.objectID
        let isDragging = compactDragState?.itemID == pinboard.objectID
        let pillSize: CGFloat = 28

        let pill = Button {
            handlePinboardSelect(pinboard.id)
        } label: {
            HStack(spacing: 5) {
                PinboardIndicator(
                    colorHex: pinboard.colorHex,
                    sign: pinboard.iconName,
                    size: 16
                )
                if isSelected {
                    Text(pinboard.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isSelected ? 10 : 0)
            .frame(width: isSelected ? nil : pillSize, height: pillSize)
            .background { compactPillBackground(isSelected: isSelected || isDropTarget) }
        }
        .buttonStyle(.plain)
        .contentShape(isSelected ? AnyShape(Capsule()) : AnyShape(Circle()))
        .opacity(isDragging ? 0.25 : 1)
        .background(compactPillFrameReporter(objectID: pinboard.objectID, isAll: false))
        .contextMenu {
            PinboardContextMenu(
                canEdit: !pinboard.isSystemMarten,
                pinboardID: pinboard.id,
                isLocked: locked,
                isUnlocked: unlocked,
                isShared: pinboard.isShared,
                isShareOwner: pinboard.shareRole == .owner,
                sharingEnabled: MartenCore.SharedPinboardsFeatureFlag.isEnabled,
                onSetLockEnabled: { enabled in handleSetPinboardLock(pinboard, enabled) },
                onUnlock: { handleRequestPinboardUnlock(pinboard) },
                onLockNow: { handleLockPinboardNow(pinboard) },
                onRename: {
                    handlePinboardSelect(pinboard.id)
                    DispatchQueue.main.async { presentVerticalPinboardEdit() }
                },
                onCustomize: {
                    handlePinboardSelect(pinboard.id)
                    DispatchQueue.main.async { presentVerticalPinboardEdit() }
                },
                onDelete: { handleDeletePinboard(pinboard) },
                onSharePinboard: { handleSharePinboard(pinboard) },
                onManageSharing: { handleManageSharing(pinboard) },
                onStopSharing: { handleStopSharing(pinboard) },
                onLeaveSharedPinboard: { handleLeaveSharedPinboard(pinboard) }
            )

            Divider()

            Button {
                beginPinboardCreate(for: nil)
            } label: {
                Label("New Pinboard…", systemImage: "plus")
            }
        }
        .accessibilityIdentifier("overlay.compactPinboard.\(pinboard.id.uuidString)")

        return pill.simultaneousGesture(compactPinboardDragGesture(for: pinboard, index: index))
    }

    // MARK: - Frame Reporting (for item drag-to-pinboard drop targets + drag reorder)

    private func compactPillFrameReporter(objectID: NSManagedObjectID, isAll: Bool) -> some View {
        GeometryReader { proxy in
            let overlayFrame = proxy.frame(in: .named(overlayCoordinateSpaceName))
            let localFrame = proxy.frame(in: .named(compactBarCoordinateSpaceName))
            Color.clear.preference(
                key: PinboardLayoutInfoKey.self,
                value: PinboardLayoutInfo(
                    tabFrames: isAll ? [:] : [objectID: localFrame],
                    overlayPinboardFrames: isAll ? [:] : [objectID: overlayFrame],
                    allOverlayFrame: isAll ? overlayFrame : nil
                )
            )
        }
    }

    // MARK: - Drag Reorder

    private func compactPinboardDragGesture(for pinboard: Pinboard, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(compactBarCoordinateSpaceName))
            .onChanged { value in
                compactHandleDragChanged(pinboard: pinboard, value: value)
            }
            .onEnded { value in
                compactHandleDragEnded(pinboard: pinboard, value: value)
            }
    }

    private func compactHandleDragChanged(pinboard: Pinboard, value: DragGesture.Value) {
        if let compactDragState, compactDragState.itemID != pinboard.objectID {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )

        let previousDropTarget = compactDropTarget

        if compactDragState == nil {
            guard let localFrame = compactPillFrames[pinboard.objectID] else { return }
            guard !compactPillFrames.isEmpty else { return }

            let handler = PinboardDragHandler(pinboards: visiblePinboards, tabSpacing: 6)
            guard let result = handler.beginDrag(
                pinboard: pinboard,
                at: localPointer,
                localFrame: localFrame,
                tabFrames: compactPillFrames
            ) else { return }

            compactDragState = result.dragState
            compactCachedOrderedFrames = result.cachedOrderedFrames
            compactDragOpacity = 1

            if let cached = compactCachedOrderedFrames {
                compactDropTarget = handler.computeDropTarget(
                    location: localPointer,
                    draggedID: pinboard.objectID,
                    orderedFrames: cached,
                    visibleBounds: .zero // compact bar is always fully visible
                )
            }
        } else {
            guard let currentState = compactDragState,
                  let cached = compactCachedOrderedFrames
            else { return }

            let handler = PinboardDragHandler(pinboards: visiblePinboards, tabSpacing: 6)
            let result = handler.updateDrag(
                currentState: currentState,
                translation: value.translation,
                newLocation: localPointer,
                cachedLocalOrderedFrames: cached,
                visibleBounds: .zero
            )

            compactDragState = result.dragState
            compactDropTarget = result.dropTarget
        }

        if compactDropTarget != previousDropTarget && compactDropTarget != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func compactHandleDragEnded(pinboard: Pinboard, value: DragGesture.Value) {
        guard let compactDragState,
              compactDragState.itemID == pinboard.objectID,
              let cached = compactCachedOrderedFrames
        else {
            compactEndDrag()
            return
        }

        let handler = PinboardDragHandler(pinboards: visiblePinboards, tabSpacing: 6)
        if let result = handler.endDrag(
            state: compactDragState,
            cachedLocalOrderedFrames: cached,
            visibleBounds: .zero
        ) {
            handlePinboardReorder(result.draggedItem, result.targetItem, insertBefore: result.insertBefore)
        }

        compactEndDrag()
    }

    private func compactEndDrag() {
        withAnimation(OverlayAnimation.dragFade) {
            compactDropTarget = nil
            compactDragOpacity = 0
        }

        let draggedID = compactDragState?.itemID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if compactDragState?.itemID == draggedID {
                compactDragState = nil
                compactCachedOrderedFrames = nil
            }
        }
    }

    // MARK: - Placeholder View

    @ViewBuilder
    private func compactPlaceholderView() -> some View {
        if let compactDropTarget,
           let localFrame = compactPillFrames[compactDropTarget.item.objectID]
        {
            let height = max(0, localFrame.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: 3, height: height)
                .offset(x: compactDropTarget.placeholderX - 1.5, y: localFrame.minY)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.06), value: compactDropTarget)
        }
    }

    // MARK: - Drag Preview View

    @ViewBuilder
    private func compactDragPreviewView() -> some View {
        if let compactDragState,
           let draggedItem = visiblePinboards.first(where: { $0.objectID == compactDragState.itemID }),
           let localFrame = compactPillFrames[draggedItem.objectID]
        {
            CompactPillDragPreview(
                pinboard: draggedItem,
                isSelected: searchModel.selectedPinboardID == draggedItem.id
            )
            .frame(width: localFrame.width, height: localFrame.height)
            .position(
                x: compactDragState.pointerLocation.x - compactDragState.cursorOffset.width,
                y: compactDragState.pointerLocation.y - compactDragState.cursorOffset.height
            )
            .opacity(compactDragOpacity)
            .animation(OverlayAnimation.dragFade, value: compactDragOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Shared Styling

    @ViewBuilder
    func compactPillBackground(isSelected: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if isSelected {
                Capsule()
                    .fill(Color.clear)
                    .glassProminentStyle()
            } else {
                Circle()
                    .fill(Color.clear)
                    .glassCircleButton()
            }
        } else {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundStrong))
            } else {
                Circle()
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
            }
        }
    }
}

// MARK: - Compact Pill Drag Preview

private struct CompactPillDragPreview: View {
    let pinboard: Pinboard
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let pillSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 5) {
            PinboardIndicator(
                colorHex: pinboard.colorHex,
                sign: pinboard.iconName,
                size: 16
            )
            if isSelected {
                Text(pinboard.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isSelected ? 10 : 0)
        .frame(width: isSelected ? nil : pillSize, height: pillSize)
        .background { dragPreviewBackground }
        .clipShape(isSelected ? AnyShape(Capsule()) : AnyShape(Circle()))
        .opacity(0.9)
        .scaleEffect(0.96)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var dragPreviewBackground: some View {
        if #available(macOS 26.0, *) {
            if isSelected {
                Capsule()
                    .fill(Color.clear)
                    .glassProminentStyle()
            } else {
                Circle()
                    .fill(Color.clear)
                    .glassCircleButton()
            }
        } else {
            if isSelected {
                Capsule()
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(DesignTokens.Opacity.backgroundStrong)
                        : Color.black.opacity(DesignTokens.Opacity.backgroundStrong))
            } else {
                Circle()
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(DesignTokens.Opacity.backgroundSubtle)
                        : Color.black.opacity(DesignTokens.Opacity.backgroundSubtle))
            }
        }
    }
}
