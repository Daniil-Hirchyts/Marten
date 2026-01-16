import ClipboardCore
import ClipboardMacServices
import CoreData
import OSLog
import SwiftUI

struct PinboardTabBar: View {
    private let tabSpacing: CGFloat = 12
    private let placeholderWidth: CGFloat = 3
    private let localCoordinateSpaceName = "PinboardBarLocalSpace"
    private let scrollSpaceName = "PinboardScrollSpace"
    private let headerButtonSize: CGFloat = 30
    private let headerButtonIconSize: CGFloat = 14
    private let tabContentHeight: CGFloat = 20
    private let tabVerticalPadding: CGFloat = 5
    private let tabHorizontalPadding: CGFloat = 10
    private let maxTabWidth: CGFloat = 160
    private let maxPinboardNameLength = 22

    let pinboards: [Pinboard]
    let selectedID: UUID?
    @Binding var editingID: NSManagedObjectID?
    @Binding var isCreating: Bool
    @Binding var draftName: String
    @Binding var draftColor: String
    var isGlobalDragActive: Bool = false  // True when any drag (including card drag) is happening

    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void
    let onRename: (Pinboard) -> Void
    let onColorChange: (Pinboard, String) -> Void
    let onDelete: (Pinboard) -> Void
    let onReorder: (Pinboard, Pinboard, Bool) -> Void
    let onReorderEnd: () -> Void
    let onMoveItem: (Pinboard, String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let coordinateSpaceName: String

    private static let allTabObjectID = NSManagedObjectID()

    @FocusState private var isFocused: Bool

    private enum CommitState {
        case none
        case cancel
        case commit
        case suppress
    }

    @StateObject private var frameManager = PinboardFrameManager()

    @State private var dragState: PinboardTabDragState?
    @State private var dragOpacity: Double = 0
    @State private var dropTarget: PinboardTabDropTarget?
    @State private var commitState: CommitState = .none
    @State private var trailingTabWidth: CGFloat = 40

    static var currentScrollOffset: CGFloat {
        _currentScrollOffset
    }
    private static var _currentScrollOffset: CGFloat = 0

    private var canReorder: Bool {
        editingID == nil && !isCreating
    }

    private let maxScrollableWidthRatio: CGFloat = 1
    private let estimatedTabWidth: CGFloat = 90
    private let scrollContentPadding: CGFloat = 20

    private var estimatedContentWidth: CGFloat {
        let count = CGFloat(pinboards.count + 1)
        if count == 0 { return 0 }
        return (count * estimatedTabWidth) + ((count - 1) * tabSpacing)
    }

    private var actualContentWidth: CGFloat {
        frameManager.contentWidth > 0 ? frameManager.contentWidth : estimatedContentWidth
    }

    private func maxAllowedScrollWidth(parentWidth: CGFloat) -> CGFloat {
        parentWidth * maxScrollableWidthRatio
    }

    private func availableScrollWidth(parentWidth: CGFloat) -> CGFloat {
        max(0, parentWidth - trailingTabWidth - tabSpacing)
    }

    private func overlayFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(coordinateSpaceName))
    }

    private func localFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(localCoordinateSpaceName))
    }

    private func scrollViewWidth(parentWidth: CGFloat) -> CGFloat {
        let contentWithPadding = actualContentWidth + (scrollContentPadding * 2)
        let maxWidth = maxAllowedScrollWidth(parentWidth: parentWidth)
        let availableWidth = availableScrollWidth(parentWidth: parentWidth)
        return min(contentWithPadding, maxWidth, availableWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: tabSpacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    pinboardsContent(isMeasuring: false)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, scrollContentPadding)
                }
                .coordinateSpace(name: scrollSpaceName)
                .frame(width: scrollViewWidth(parentWidth: proxy.size.width))
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.025),
                            .init(color: .black, location: 0.975),
                            .init(color: .clear, location: 1),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                ZStack(alignment: .leading) {
                    if isCreating {
                        editorView(pinboard: nil)
                    } else {
                        Button(action: onCreate) {
                            Image(systemName: "plus")
                                .font(.system(size: headerButtonIconSize, weight: .semibold))
                                .frame(width: headerButtonSize, height: headerButtonSize)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(editorOverlayFrame: overlayFrame(from: proxy))
                        )
                    }
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .coordinateSpace(name: localCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                placeholderView()
            }
            .overlay(alignment: .topLeading) {
                dragPreviewView()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            frameManager.suppressUpdates = (dragState != nil || isGlobalDragActive)
            if !layout.tabFrames.isEmpty {
                frameManager.updateTabFrames(layout.tabFrames)
            }
            if let offset = layout.scrollOffset {
                Self._currentScrollOffset = offset
            }
            if let w = layout.editorOverlayFrame?.width {
                trailingTabWidth = w
            }
        }
        .onChange(of: draftName) { newValue in
            let clamped = String(newValue.prefix(maxPinboardNameLength))
            if clamped != newValue {
                draftName = clamped
            }
        }
        .onChange(of: pinboards.count) { _ in
            frameManager.shouldReportFrames = true
        }
    }

    @ViewBuilder
    private func pinboardsContent(isMeasuring: Bool) -> some View {
        HStack(spacing: tabSpacing) {
            PinboardTab(
                title: "All", iconName: "tray", colorHex: nil, isSelected: selectedID == nil,
                minWidth: 60, maxWidth: maxTabWidth
            ) {
                onSelect(nil)
            }
            .background(
                GeometryReader { proxy in
                    if !isMeasuring {
                        let overlayFrame = overlayFrame(from: proxy)
                        let minX = proxy.frame(in: .named(scrollSpaceName)).minX

                        if frameManager.shouldReportFrames {
                            let barLocalFrame = localFrame(from: proxy)

                            Color.clear.preference(
                                key: PinboardLayoutInfoKey.self,
                                value: PinboardLayoutInfo(
                                    tabFrames: [Self.allTabObjectID: barLocalFrame],
                                    allOverlayFrame: overlayFrame,
                                    scrollOffset: minX
                                )
                            )
                        } else {
                            Color.clear.preference(
                                key: PinboardLayoutInfoKey.self,
                                value: PinboardLayoutInfo(
                                    allOverlayFrame: overlayFrame, scrollOffset: minX)
                            )
                        }
                    }
                }
            )

            ForEach(Array(pinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                if editingID == pinboard.objectID {
                    editorView(pinboard: pinboard)
                } else {
                    pinboardView(pinboard: pinboard, index: index + 1, isMeasuring: isMeasuring)
                }
            }
        }
    }

    @ViewBuilder
    private func editorView(pinboard: Pinboard?) -> some View {
        HStack(spacing: 6) {
            ColorPicker(selectedHex: pinboard?.colorHex ?? draftColor) { newColor in
                draftColor = newColor
                if let pinboard {
                    onColorChange(pinboard, newColor)
                }
                DispatchQueue.main.async {
                    isFocused = true
                }
                commitState = .suppress
            }

            ZStack(alignment: .leading) {
                Text(draftName.isEmpty ? "Name" : draftName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.clear)
                    .padding(.vertical, 0)
                    .layoutPriority(1)

                if draftName.isEmpty {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .allowsHitTesting(false)
                }
                TextField("", text: $draftName) { editing in
                    if !editing {
                        handleBlurCommit()
                    }
                } onCommit: {
                    handleCommitButton()
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .accentColor(.white)
                .focused($isFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
            }
            .frame(minWidth: 40)
        }
        .frame(minHeight: tabContentHeight, alignment: .center)
        .padding(.vertical, tabVerticalPadding)
        .padding(.horizontal, tabHorizontalPadding)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(isFocused ? 0.3 : 0), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: maxTabWidth, alignment: .leading)
        .frame(height: headerButtonSize)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PinboardLayoutInfoKey.self,
                    value: PinboardLayoutInfo(editorOverlayFrame: overlayFrame(from: proxy))
                )
            }
        )
    }

    @ViewBuilder
    private func pinboardView(pinboard: Pinboard, index: Int, isMeasuring: Bool = false)
        -> some View
    {
        let isDragging = dragState?.itemID == pinboard.objectID

        let base = PinboardTab(
            title: pinboard.name, colorHex: pinboard.colorHex,
            isSelected: selectedID == pinboard.id, maxWidth: maxTabWidth
        ) {
            onSelect(pinboard.id)
        }
        .opacity(isDragging ? 0.25 : 1)
        .background(
            GeometryReader { proxy in
                if !isMeasuring {
                    let overlayFrame = overlayFrame(from: proxy)

                    if frameManager.shouldReportFrames {
                        let localFrame = localFrame(from: proxy)

                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(
                                tabFrames: [pinboard.objectID: localFrame],
                                overlayPinboardFrames: [pinboard.objectID: overlayFrame]
                            )
                        )
                    } else {
                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(overlayPinboardFrames: [
                                pinboard.objectID: overlayFrame
                            ])
                        )
                    }
                }
            }
        )
        .contextMenu {
            PinboardContextMenu(
                canEdit: !pinboard.isSystemClipboard,
                onRename: { onRename(pinboard) },
                onColorChange: { color in onColorChange(pinboard, color) },
                onDelete: { onDelete(pinboard) }
            )
        }

        if canReorder {
            base.simultaneousGesture(dragGesture(for: pinboard, index: index))
        } else {
            base
        }
    }

    private func dragGesture(for pinboard: Pinboard, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(localCoordinateSpaceName))
            .onChanged { value in
                handleDragChanged(pinboard: pinboard, value: value)
            }
            .onEnded { value in
                handleDragEnded(pinboard: pinboard, value: value)
            }
    }

    private func handleDragChanged(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder else { return }

        if let dragState, dragState.itemID != pinboard.objectID {
            return
        }

        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )

        if dragState == nil {
            guard let localFrame = frameManager.latestTabFrames[pinboard.objectID] else {
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

            if let cachedLocal = frameManager.cachedOrderedFrames {
                dropTarget = handler.computeDropTarget(
                    location: localPointer,
                    draggedID: pinboard.objectID,
                    orderedFrames: cachedLocal
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
                cachedLocalOrderedFrames: cachedLocal
            )

            dragState = result.dragState
            dropTarget = result.dropTarget
        }
    }

    private func handleDragEnded(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder,
            let dragState,
            dragState.itemID == pinboard.objectID,
            let cachedLocal = frameManager.cachedOrderedFrames
        else {
            return
        }

        let handler = PinboardDragHandler(pinboards: pinboards, tabSpacing: tabSpacing)
        if let result = handler.endDrag(state: dragState, cachedLocalOrderedFrames: cachedLocal) {
            onReorder(result.draggedItem, result.targetItem, result.insertBefore)
            onReorderEnd()
        }

        endDrag(for: dragState.itemID)
    }

    private func endDrag(for itemID: NSManagedObjectID) {
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

    private func handleBlurCommit() {
        guard isCreating || editingID != nil else { return }

        DispatchQueue.main.async {
            switch commitState {
            case .cancel:
                commitState = .none
                return
            case .commit:
                commitState = .none
                return
            case .suppress:
                commitState = .none
                return
            case .none:
                break
            }

            if let window = NSApp.windows.first(where: { $0.isKeyWindow }), window.isVisible {
                onCommit()
            } else {
                onCancel()
            }
        }
    }

    private func handleCommitButton() {
        commitState = .commit
        onCommit()
        isFocused = false
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        if let dropTarget,
            let localFrame = frameManager.latestTabFrames[dropTarget.item.objectID]
        {
            let height = max(0, localFrame.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.5))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 0)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func dragPreviewView() -> some View {
        if let dragState,
            let draggedItem = pinboards.first(where: { $0.objectID == dragState.itemID }),
            let localFrame = frameManager.latestTabFrames[draggedItem.objectID]
        {
            PinboardTabPreview(title: draggedItem.name, colorHex: draggedItem.colorHex)
                .frame(width: localFrame.width, height: localFrame.height)
                .position(
                    x: dragState.pointerLocation.x - dragState.cursorOffset.width,
                    y: dragState.pointerLocation.y - dragState.cursorOffset.height
                )
                .opacity(dragOpacity)
                .animation(.easeOut(duration: 0.1), value: dragOpacity)
                .allowsHitTesting(false)
        }
    }
}

private struct ColorPicker: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(PinboardPalette.all, id: \.hex) { color in
                Button {
                    onSelect(color.hex)
                } label: {
                    HStack {
                        Image(nsImage: .colorCircle(hex: color.hex))
                        Text(color.name)
                    }
                }
            }
        } label: {
            Image(nsImage: .colorCircle(hex: selectedHex))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct PinboardTabPreview: View {
    let title: String
    let colorHex: String?

    var body: some View {
        HStack(spacing: 6) {
            if let colorHex {
                Circle()
                    .fill(Color(hex: colorHex, fallback: .gray))
                    .frame(width: 8, height: 8)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 20)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.2))
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}
