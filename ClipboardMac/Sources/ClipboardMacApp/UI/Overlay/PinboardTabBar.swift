import ClipboardCore
import ClipboardMacServices
import CoreData
import OSLog
import SwiftUI

/// Preference key for tracking scroll view bounds
private struct ScrollViewBoundsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

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
    let window: NSWindow?
    var onPreviewUpdate: ((PinboardDragPreviewData?) -> Void)? = nil

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

    @EnvironmentObject private var frameCoordinator: FrameCoordinator
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
    @State private var autoScrollTimer: Timer?
    @State private var scrollViewBounds: CGRect = .zero
    @State private var currentScrollProxy: ScrollViewProxy?
    @Environment(\.colorScheme) private var colorScheme

    private let autoScrollEdgeInset: CGFloat = 40
    private let autoScrollSpeed: CGFloat = 4

    private var canReorder: Bool {
        editingID == nil && !isCreating
    }

    private let scrollContentPadding: CGFloat = 20

    /// Calculates the minimum width needed for all tabs, without estimation.
    /// Uses actual content measurements when available.
    private var measuredContentWidth: CGFloat {
        frameManager.contentWidth
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

    /// Returns scroll view width that exactly fits content, clamped to available space.
    /// Uses measured content width for stability once frames are available.
    private func scrollViewWidth(parentWidth: CGFloat) -> CGFloat {
        let availableWidth = availableScrollWidth(parentWidth: parentWidth)

        // If we have measured content, use it; otherwise fill available space
        if measuredContentWidth > 0 {
            let contentWithPadding = measuredContentWidth + (scrollContentPadding * 2)
            return min(contentWithPadding, availableWidth)
        }

        // Before first measurement, use available width (content will constrain itself)
        return availableWidth
    }

    /// Returns true if scrolling should be disabled (content fits within available space)
    private func shouldDisableScroll(parentWidth: CGFloat) -> Bool {
        guard measuredContentWidth > 0 else { return true }
        let availableWidth = availableScrollWidth(parentWidth: parentWidth)
        let contentWithPadding = measuredContentWidth + (scrollContentPadding * 2)
        return contentWithPadding <= availableWidth
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 6) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        pinboardsContent(isMeasuring: false)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, scrollContentPadding)
                    }
                    .scrollDisabled(shouldDisableScroll(parentWidth: proxy.size.width))
                    .coordinateSpace(name: scrollSpaceName)
                    .frame(width: scrollViewWidth(parentWidth: proxy.size.width))
                    .background(
                        GeometryReader { scrollGeo in
                            let bounds = scrollGeo.frame(in: .named(localCoordinateSpaceName))
                            Color.clear
                                .preference(key: ScrollViewBoundsKey.self, value: bounds)
                                .onAppear {
                                    scrollViewBounds = bounds
                                    currentScrollProxy = scrollProxy
                                }
                        }
                    )
                    .onPreferenceChange(ScrollViewBoundsKey.self) { newBounds in
                        scrollViewBounds = newBounds
                    }
                    .onChange(of: dragState) { newDragState, _ in
                        handleAutoScrollStateChange(newDragState, scrollProxy: scrollProxy)
                    }
                }
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
                            if #available(macOS 26.0, *) {
                                Image(systemName: "plus")
                                    .font(.system(size: headerButtonIconSize, weight: .semibold))
                                    .frame(width: headerButtonSize, height: headerButtonSize)
                                    .glassCircleButton()
                                    .contentShape(Circle())
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: headerButtonIconSize, weight: .semibold))
                                    .frame(width: headerButtonSize, height: headerButtonSize)
                                    .background(
                                        Circle()
                                            .fill(
                                                Color.white.opacity(
                                                    DesignTokens.Opacity.backgroundMedium))
                                    )
                                    .contentShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .accessibilityIdentifier("overlay.pinboard.add")
                        .accessibilityLabel("Add pinboard")
                        .accessibilityHint("Creates a new pinboard")
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
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            frameManager.suppressUpdates = (dragState != nil || isGlobalDragActive)
            if !layout.tabFrames.isEmpty {
                frameManager.updateTabFrames(layout.tabFrames)
            }
            if let offset = layout.scrollOffset {
                frameCoordinator.updateCurrentPinboardScrollOffset(offset)
            }
            if let w = layout.editorOverlayFrame?.width {
                trailingTabWidth = w
            }
        }
        .onChange(of: draftName) { newValue, _ in
            let clamped = String(newValue.prefix(maxPinboardNameLength))
            if clamped != newValue {
                draftName = clamped
            }
        }
        .onChange(of: pinboards.count) { _, _ in
            // Pinboard count changed, clear caches
            frameManager.clearCaches()
        }
        .onAppear {
            // Ensure clean state when view appears
            frameManager.clearCaches()
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
            .id("all")
            .accessibilityIdentifier("overlay.pinboard.all")
            .accessibilityLabel("All items")
            .accessibilityValue(selectedID == nil ? "Selected" : "Not selected")
            .accessibilityHint(pinboardHint(title: "All items", isAll: true))
            .accessibilityElement(children: .ignore)
            .background(
                GeometryReader { proxy in
                    if !isMeasuring {
                        let overlayFrame = overlayFrame(from: proxy)
                        let minX = proxy.frame(in: .named(scrollSpaceName)).minX
                        let barLocalFrame = localFrame(from: proxy)

                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(
                                tabFrames: [Self.allTabObjectID: barLocalFrame],
                                allOverlayFrame: overlayFrame,
                                scrollOffset: minX
                            )
                        )
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
                    .foregroundStyle(.clear)
                    .padding(.vertical, 0)
                    .layoutPriority(1)

                if draftName.isEmpty {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(editorPlaceholderColor)
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
                .foregroundStyle(editorTextColor)
                .tint(editorTextColor)
                .focused($isFocused)
                .accessibilityIdentifier("overlay.pinboard.editor.name")
                .accessibilityLabel("Pinboard name")
                .accessibilityValue(draftName.isEmpty ? "Empty" : draftName)
                .accessibilityHint("Enter a pinboard name")
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
        .overlay(
            Group {
                if #available(macOS 26.0, *) {
                    EmptyView()
                } else {
                    Capsule()
                        .stroke(
                            (colorScheme == .dark ? Color.white : Color.black).opacity(isFocused ? DesignTokens.Opacity.borderStrong : 0),
                            lineWidth: 1)
                }
            }
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
        .id(pinboard.id)
        .accessibilityIdentifier("overlay.pinboard.\(pinboard.id.uuidString)")
        .accessibilityLabel(pinboard.name)
        .accessibilityValue(selectedID == pinboard.id ? "Selected" : "Not selected")
        .accessibilityHint(pinboardHint(title: pinboard.name, isAll: false))
        .accessibilityElement(children: .ignore)
        .opacity(isDragging ? 0.25 : 1)
        .background(
            GeometryReader { proxy in
                if !isMeasuring {
                    let overlayFrame = overlayFrame(from: proxy)
                    let localFrame = localFrame(from: proxy)

                    Color.clear.preference(
                        key: PinboardLayoutInfoKey.self,
                        value: PinboardLayoutInfo(
                            tabFrames: [pinboard.objectID: localFrame],
                            overlayPinboardFrames: [pinboard.objectID: overlayFrame]
                        )
                    )
                }
            }
        )
        .contextMenu {
            PinboardContextMenu(
                canEdit: !pinboard.isSystemClipboard,
                pinboardID: pinboard.id,
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
                Logger.drag.debug("Cannot begin drag: frame not found for pinboard")
                return
            }

            // Ensure we have valid frame data before starting drag
            guard !frameManager.latestTabFrames.isEmpty else {
                Logger.drag.debug("Cannot begin drag: no tab frames available")
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

            // Send initial preview data
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

            // Update preview data during drag
            if let localFrame = frameManager.latestTabFrames[pinboard.objectID] {
                updatePreviewData(for: pinboard, localFrame: localFrame)
            }

            // Check for auto-scroll near edges
            if let scrollProxy = currentScrollProxy {
                checkAutoScroll(at: localPointer, scrollProxy: scrollProxy)
            }
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

    private func endDrag(for itemID: NSManagedObjectID) {
        stopAutoScroll()

        // Clear preview immediately
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

    private func updatePreviewData(for pinboard: Pinboard, localFrame: CGRect) {
        let data = PinboardDragPreviewData(
            title: pinboard.name,
            colorHex: pinboard.colorHex,
            size: localFrame.size,
            opacity: dragOpacity
        )
        onPreviewUpdate?(data)
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

    private func pinboardHint(title: String, isAll: Bool) -> String {
        var parts: [String] = []
        parts.append(isAll ? "Shows all items" : "Shows items in \(title)")
        if !isAll && canReorder {
            parts.append("Drag to reorder pinboards")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Editor Colors

    private var editorTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var editorPlaceholderColor: Color {
        colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.3)
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        if let dropTarget,
            let localFrame = frameManager.latestTabFrames[dropTarget.item.objectID],
            isPlaceholderVisible(at: dropTarget.placeholderX)
        {
            let height = max(0, localFrame.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 0)
                .transition(.opacity)
        }
    }

    /// Checks if a placeholder at the given X position is within visible scroll bounds
    private func isPlaceholderVisible(at x: CGFloat) -> Bool {
        guard !scrollViewBounds.isEmpty else { return true }
        // Allow a small margin outside the bounds for better UX
        let margin: CGFloat = 10
        return x >= scrollViewBounds.minX - margin && x <= scrollViewBounds.maxX + margin
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
                .accessibilityHidden(true)
        }
    }

    // MARK: - Auto-Scroll

    private func handleAutoScrollStateChange(
        _ newState: PinboardTabDragState?, scrollProxy: ScrollViewProxy
    ) {
        if newState == nil {
            stopAutoScroll()
        }
    }

    private func startAutoScroll(direction: AutoScrollDirection, scrollProxy: ScrollViewProxy) {
        stopAutoScroll()

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [self] _ in
            guard let dragState = dragState else {
                stopAutoScroll()
                return
            }

            // Find the target pinboard to scroll to based on direction
            let sortedPinboards = pinboards.sorted { lhs, rhs in
                let lhsFrame = frameManager.latestTabFrames[lhs.objectID] ?? .zero
                let rhsFrame = frameManager.latestTabFrames[rhs.objectID] ?? .zero
                return lhsFrame.minX < rhsFrame.minX
            }

            guard !sortedPinboards.isEmpty else { return }

            let currentX = dragState.pointerLocation.x

            switch direction {
            case .leading:
                // Find the first pinboard to the left of current position
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
                    // Scroll to "All" tab
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo("all", anchor: .leading)
                    }
                }
            case .trailing:
                // Find the first pinboard to the right of current position
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

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func checkAutoScroll(at location: CGPoint, scrollProxy: ScrollViewProxy) {
        guard dragState != nil, !scrollViewBounds.isEmpty else {
            stopAutoScroll()
            return
        }

        let relativeX = location.x - scrollViewBounds.minX

        if relativeX < autoScrollEdgeInset {
            // Near leading edge
            if autoScrollTimer == nil {
                startAutoScroll(direction: .leading, scrollProxy: scrollProxy)
            }
        } else if relativeX > scrollViewBounds.width - autoScrollEdgeInset {
            // Near trailing edge
            if autoScrollTimer == nil {
                startAutoScroll(direction: .trailing, scrollProxy: scrollProxy)
            }
        } else {
            stopAutoScroll()
        }
    }

    private enum AutoScrollDirection {
        case leading
        case trailing
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
                .accessibilityIdentifier("overlay.pinboard.editor.color.\(color.hex)")
            }
        } label: {
            Image(nsImage: .colorCircle(hex: selectedHex))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("overlay.pinboard.editor.color")
        .accessibilityLabel("Pinboard color")
        .accessibilityValue(selectedColorName)
        .accessibilityHint("Choose a pinboard color")
    }

    private var selectedColorName: String {
        PinboardPalette.all.first(where: { $0.hex == selectedHex })?.name ?? selectedHex
    }
}

private struct PinboardTabPreview: View {
    let title: String
    let colorHex: String?
    @Environment(\.colorScheme) private var colorScheme


    var body: some View {
        HStack(spacing: 6) {
            if let colorHex {
                Circle()
                    .fill(Color(hex: colorHex, fallback: .gray))
                    .frame(width: 8, height: 8)
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
