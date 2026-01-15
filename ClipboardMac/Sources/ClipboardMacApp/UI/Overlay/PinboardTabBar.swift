import ClipboardCore
import ClipboardMacServices
import CoreData
import OSLog
import SwiftUI

// Debug flag - set to true to see logs in terminal
private let DEBUG_DRAG = false

private func debugLog(_ message: String) {
    if DEBUG_DRAG {
        print("[PinboardTabBar] \(message)")
        fflush(stdout)
    }
}

// Approximate equality for CGRect to handle floating-point precision issues
// Using higher tolerance (5.0) to prevent layout jitter from triggering updates
private func framesApproximatelyEqual(
    _ lhs: [NSManagedObjectID: CGRect],
    _ rhs: [NSManagedObjectID: CGRect],
    tolerance: CGFloat = 5.0
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, lhsRect) in lhs {
        guard let rhsRect = rhs[key] else { return false }
        if abs(lhsRect.origin.x - rhsRect.origin.x) > tolerance ||
           abs(lhsRect.origin.y - rhsRect.origin.y) > tolerance ||
           abs(lhsRect.size.width - rhsRect.size.width) > tolerance ||
           abs(lhsRect.size.height - rhsRect.size.height) > tolerance {
            return false
        }
    }
    return true
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

    @FocusState private var isFocused: Bool
    // Content-space frames for drop target calculation (reactive for count changes)
    @State private var tabFrames: [NSManagedObjectID: CGRect] = [:]
    // Local-space frames for drag preview and placeholder rendering (reactive for count changes)
    @State private var localTabFrames: [NSManagedObjectID: CGRect] = [:]
    // Non-reactive frame storage - always up to date, doesn't trigger re-renders
    private static var latestTabFrames: [NSManagedObjectID: CGRect] = [:]
    private static var latestLocalTabFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var dragState: DragState?
    @State private var dragOpacity: Double = 0
    @State private var dropTarget: DropTarget?
    @State private var cancelRequested = false
    @State private var commitRequested = false
    @State private var suppressNextBlurCommit = false
    @State private var contentWidth: CGFloat = 0
    @State private var trailingTabWidth: CGFloat = 40 // Default or estimated
    @State private var shouldReportFrames: Bool = true  // Only report frames when needed, not during scroll
    
    // Non-reactive scroll offset - updated during scroll but doesn't trigger re-renders
    private static var latestScrollOffset: CGFloat = 0
    
    // Public accessor for OverlayRootView to capture scroll offset
    static var currentScrollOffset: CGFloat { latestScrollOffset }
    // Cached ordered frames (content-space) to avoid repeated sorting during drag
    @State private var cachedOrderedFrames: [(item: Pinboard, frame: CGRect)]?
    // Cached local-space ordered frames for placeholder rendering
    @State private var cachedLocalOrderedFrames: [(item: Pinboard, frame: CGRect)]?

    private let contentSpaceName = "PinboardContentSpace"
    private var canReorder: Bool {
        editingID == nil && !isCreating
    }

    private let maxScrollableWidthRatio: CGFloat = 1 // Maximum width as percentage of overlay width
    private let estimatedTabWidth: CGFloat = 90 // Estimated average tab width
    private let scrollContentPadding: CGFloat = 20 // Padding on each side inside scroll
    
    // Computed property for estimated content width based on number of pinboards (including All)
    private var estimatedContentWidth: CGFloat {
        let count = CGFloat(pinboards.count + 1) // +1 for "All" tab
        if count == 0 { return 0 }
        return (count * estimatedTabWidth) + ((count - 1) * tabSpacing)
    }

    // Use actual measured width if available, otherwise estimate
    private var actualContentWidth: CGFloat {
        contentWidth > 0 ? contentWidth : estimatedContentWidth
    }

    private func maxAllowedScrollWidth(parentWidth: CGFloat) -> CGFloat {
        parentWidth * maxScrollableWidthRatio
    }

    private func availableScrollWidth(parentWidth: CGFloat) -> CGFloat {
        max(0, parentWidth - trailingTabWidth - tabSpacing)
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
                // Scrollable Pinboards (including "All" tab) - adapts to content width up to max
                ScrollView(.horizontal, showsIndicators: false) {
                    pinboardsContent(isMeasuring: false)
                        .padding(.horizontal, scrollContentPadding)
                        .coordinateSpace(name: contentSpaceName)
                }
                .coordinateSpace(name: scrollSpaceName)
                .frame(width: scrollViewWidth(parentWidth: proxy.size.width))
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.025),
                            .init(color: .black, location: 0.975),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // Fixed Creation View
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
                            key: PinboardEditorFrameKey.self,
                            value: proxy.frame(in: .named(coordinateSpaceName))
                        )
                    }
                )
            }
            .fixedSize(horizontal: true, vertical: false) // Let HStack take only the width it needs
            .coordinateSpace(name: localCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                placeholderView()
            }
            .overlay(alignment: .topLeading) {
                dragPreviewView()
            }
            .frame(maxWidth: .infinity, alignment: .center) // Center the whole bar
        }
        .onPreferenceChange(TabFrameKey.self) { frames in
            // Always store in non-reactive storage (doesn't trigger re-renders)
            Self.latestTabFrames = frames
            
            // Skip reactive updates during ANY drag to prevent re-render loops
            guard dragState == nil && !isGlobalDragActive else { return }
            
            // Update if count changed OR keys changed (different pinboards)
            let countChanged = frames.count != tabFrames.count
            let keysChanged = Set(frames.keys) != Set(tabFrames.keys)

            if countChanged || keysChanged {
                tabFrames = frames
                cachedOrderedFrames = nil
                cachedLocalOrderedFrames = nil
            }

            // Update content width
            if !frames.isEmpty {
                let minX = frames.values.map { $0.minX }.min() ?? 0
                let maxX = frames.values.map { $0.maxX }.max() ?? 0
                let measuredWidth = maxX - minX
                // Always update if count changed, otherwise only if significant change
                if measuredWidth > 0 && (countChanged || abs(contentWidth - measuredWidth) > 10) {
                    contentWidth = measuredWidth
                }
            } else {
                // Reset content width when there are no frames
                contentWidth = 0
            }
        }
        .onPreferenceChange(LocalTabFrameKey.self) { frames in
            // Always store in non-reactive storage (doesn't trigger re-renders)
            Self.latestLocalTabFrames = frames
            
            // Skip reactive updates during ANY drag
            guard dragState == nil && !isGlobalDragActive else { return }
            
            // Update if count changed OR keys changed
            let countChanged = frames.count != localTabFrames.count
            let keysChanged = Set(frames.keys) != Set(localTabFrames.keys)
            if countChanged || keysChanged {
                localTabFrames = frames
                cachedLocalOrderedFrames = nil
            }
        }
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            // Store scroll offset non-reactively (doesn't trigger re-renders)
            Self.latestScrollOffset = offset
            
            // Turn off frame reporting after initial capture
            if shouldReportFrames {
                shouldReportFrames = false
            }
        }
        .onPreferenceChange(PinboardEditorFrameKey.self) { rect in
             if let w = rect?.width { trailingTabWidth = w }
        }
        .onChange(of: draftName) { newValue in
            let clamped = String(newValue.prefix(maxPinboardNameLength))
            if clamped != newValue {
                draftName = clamped
            }
        }
        .onChange(of: pinboards.count) { _ in
            // Re-enable frame reporting when pinboards change
            shouldReportFrames = true
        }
    }

    @ViewBuilder
    private func pinboardsContent(isMeasuring: Bool) -> some View {
        HStack(spacing: tabSpacing) {
            // "All" tab as first item in the list
            PinboardTab(title: "All", iconName: "tray", colorHex: nil, isSelected: selectedID == nil, minWidth: 60, maxWidth: maxTabWidth) {
                onSelect(nil)
            }
            .background(
                GeometryReader { proxy in
                    if !isMeasuring {
                        let overlayFrame = proxy.frame(in: .named(coordinateSpaceName))
                        let minX = proxy.frame(in: .named(scrollSpaceName)).minX
                        
                        // Always report overlay frame and scroll offset (for card drop detection)
                        // Only report internal frames when needed (for pinboard reordering)
                        if shouldReportFrames {
                            let contentFrame = proxy.frame(in: .named(contentSpaceName))
                            let barLocalFrame = proxy.frame(in: .named(localCoordinateSpaceName))
                            
                            Color.clear
                                .preference(key: TabFrameKey.self, value: [NSManagedObjectID(): contentFrame])
                                .preference(key: LocalTabFrameKey.self, value: [NSManagedObjectID(): barLocalFrame])
                                .preference(key: PinboardAllFrameKey.self, value: overlayFrame)
                                .preference(key: ScrollOffsetKey.self, value: minX)
                        } else {
                            // Always report overlay frame and scroll offset (stored non-reactively)
                            Color.clear
                                .preference(key: PinboardAllFrameKey.self, value: overlayFrame)
                                .preference(key: ScrollOffsetKey.self, value: minX)
                        }
                    }
                }
            )
            
            // Other pinboards
            ForEach(Array(pinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                if editingID == pinboard.objectID {
                    editorView(pinboard: pinboard)
                } else {
                    pinboardView(pinboard: pinboard, index: index + 1, isMeasuring: isMeasuring) // +1 because "All" is index 0
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
                suppressNextBlurCommit = true
            }

            ZStack(alignment: .leading) {
                // Auto-sizing hidden text
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
                // Ensure focus on appear
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
        // Focus border
        .overlay(
             Capsule()
                 .stroke(Color.white.opacity(isFocused ? 0.3 : 0), lineWidth: 1)
        )
        // Fixed height, dynamic width
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: maxTabWidth, alignment: .leading)
        .frame(height: headerButtonSize)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PinboardEditorFrameKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
            }
        )
    }

    @ViewBuilder
    private func pinboardView(pinboard: Pinboard, index: Int, isMeasuring: Bool = false) -> some View {
        let isDragging = dragState?.itemID == pinboard.objectID
        
        let base = PinboardTab(title: pinboard.name, colorHex: pinboard.colorHex, isSelected: selectedID == pinboard.id, maxWidth: maxTabWidth) {
            onSelect(pinboard.id)
        }
        .opacity(isDragging ? 0.25 : 1)
        .background(
             GeometryReader { proxy in
                  if !isMeasuring {
                      let overlayFrame = proxy.frame(in: .named(coordinateSpaceName))
                      
                      // Always report overlay frame (for card drop detection)
                      // Only report internal frames when needed (for pinboard reordering)
                      if shouldReportFrames {
                          let contentFrame = proxy.frame(in: .named(contentSpaceName))
                          let localFrame = proxy.frame(in: .named(localCoordinateSpaceName))
                          
                          Color.clear
                             .preference(key: TabFrameKey.self, value: [pinboard.objectID: contentFrame])
                             .preference(key: LocalTabFrameKey.self, value: [pinboard.objectID: localFrame])
                             .preference(key: PinboardFrameKey.self, value: [pinboard.objectID: overlayFrame])
                      } else {
                          // Always report overlay frame (stored non-reactively for card drops)
                          Color.clear
                             .preference(key: PinboardFrameKey.self, value: [pinboard.objectID: overlayFrame])
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
        // Use local coordinate space for stable positioning during scroll
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

        // Current pointer location in local coordinate space
        let localPointer = CGPoint(
            x: value.startLocation.x + value.translation.width,
            y: value.startLocation.y + value.translation.height
        )

        if dragState == nil {
            // If frames are missing, trigger a refresh and abort this attempt
            // The next gesture event will have fresh frames
            if Self.latestLocalTabFrames[pinboard.objectID] == nil ||
               Self.latestTabFrames[pinboard.objectID] == nil {
                if !shouldReportFrames {
                    shouldReportFrames = true
                }
                return
            }
            
            // Get frames from non-reactive storage (always up to date)
            guard let localFrame = Self.latestLocalTabFrames[pinboard.objectID],
                  let contentFrame = Self.latestTabFrames[pinboard.objectID] else {
                debugLog("Drag start failed: missing frames for \(pinboard.name)")
                return
            }
            
            // Update reactive state with latest frames at drag start
            tabFrames = Self.latestTabFrames
            localTabFrames = Self.latestLocalTabFrames
            
            // Calculate cursor offset from item center
            let cursorOffset = CGSize(
                width: value.startLocation.x - localFrame.midX,
                height: value.startLocation.y - localFrame.midY
            )
            
            // Cache ordered frames at drag start (both content and local space)
            cachedOrderedFrames = computeOrderedFrames()
            cachedLocalOrderedFrames = computeLocalOrderedFrames()
            
            debugLog("Drag started: item=\(pinboard.name), scrollOffset=\(Self.latestScrollOffset)")
            
            dragState = DragState(
                itemID: pinboard.objectID,
                pointerLocation: localPointer,
                localBaseCenter: CGPoint(x: localFrame.midX, y: localFrame.midY),
                contentBaseCenter: CGPoint(x: contentFrame.midX, y: contentFrame.midY),
                initialScrollOffset: Self.latestScrollOffset,
                translation: .zero,
                cursorOffset: cursorOffset
            )
            dragOpacity = 1
        } else if var state = dragState {
            state.pointerLocation = localPointer
            state.translation = value.translation
            dragState = state
        }

        // Use local pointer directly for drop target (local-space calculation)
        let target = computeDropTarget(location: localPointer, draggedID: pinboard.objectID)
        // Update without animation during drag for better performance
        dropTarget = target
    }
    
    private func handleDragEnded(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder,
              let dragState,
              dragState.itemID == pinboard.objectID else {
            return
        }

        debugLog("Drag ended: item=\(pinboard.name)")
        
        // Use local pointer directly for drop target
        if let target = computeDropTarget(location: dragState.pointerLocation, draggedID: dragState.itemID),
           let draggedItem = pinboards.first(where: { $0.objectID == dragState.itemID }) {
            debugLog("Reorder: \(draggedItem.name) -> \(target.item.name), insertBefore=\(target.insertBefore)")
            onReorder(draggedItem, target.item, target.insertBefore)
            onReorderEnd()
        }

        endDrag(for: dragState.itemID)
    }

    private func endDrag(for itemID: NSManagedObjectID) {
        debugLog("endDrag called")
        
        // Animate out
        withAnimation(.easeOut(duration: 0.1)) {
            dropTarget = nil
            dragOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if dragState?.itemID == itemID {
                dragState = nil
                cachedOrderedFrames = nil
                cachedLocalOrderedFrames = nil
                debugLog("Drag state cleared")
            }
        }
    }

    /// Computes drop target using local-space frames (stable during drag)
    private func computeDropTarget(location: CGPoint, draggedID: NSManagedObjectID) -> DropTarget? {
        // Use local-space frames for hit testing
        let ordered = localOrderedFrames()
        guard let draggedIndex = ordered.firstIndex(where: { $0.item.objectID == draggedID }),
              let first = ordered.first,
              let last = ordered.last else {
            return nil
        }

        let locationX = location.x
        let candidate: DropTarget?

        if locationX < first.frame.minX {
            let pX = computePlaceholderX(for: ordered, targetIndex: 0, insertBefore: true)
            candidate = DropTarget(item: first.item, insertBefore: true, placeholderX: pX)
        } else if locationX > last.frame.maxX {
            let pX = computePlaceholderX(for: ordered, targetIndex: ordered.count - 1, insertBefore: false)
            candidate = DropTarget(item: last.item, insertBefore: false, placeholderX: pX)
        } else if let hit = ordered.first(where: { $0.frame.minX <= locationX && locationX <= $0.frame.maxX }) {
            let insertBefore = locationX < hit.frame.midX
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == hit.item.objectID }) ?? 0
            let pX = computePlaceholderX(for: ordered, targetIndex: targetIndex, insertBefore: insertBefore)
            candidate = DropTarget(item: hit.item, insertBefore: insertBefore, placeholderX: pX)
        } else if let next = ordered.first(where: { locationX < $0.frame.minX }) {
            let targetIndex = ordered.firstIndex(where: { $0.item.objectID == next.item.objectID }) ?? 0
            let pX = computePlaceholderX(for: ordered, targetIndex: targetIndex, insertBefore: true)
            candidate = DropTarget(item: next.item, insertBefore: true, placeholderX: pX)
        } else {
            candidate = nil
        }

        guard let candidate,
              let targetIndex = ordered.firstIndex(where: { $0.item.objectID == candidate.item.objectID }),
              !isNoOp(draggedIndex: draggedIndex, targetIndex: targetIndex, insertBefore: candidate.insertBefore) else {
            return nil
        }

        return candidate
    }

    /// Calculates placeholder X position in local-space
    private func computePlaceholderX(for ordered: [(item: Pinboard, frame: CGRect)], targetIndex: Int, insertBefore: Bool) -> CGFloat {
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

    /// Returns cached local ordered frames during drag, or computes fresh ones
    private func localOrderedFrames() -> [(item: Pinboard, frame: CGRect)] {
        if let cached = cachedLocalOrderedFrames {
            return cached
        }
        return computeLocalOrderedFrames()
    }
    
    /// Returns cached content-space ordered frames during drag, or computes fresh ones
    private func orderedFrames() -> [(item: Pinboard, frame: CGRect)] {
        if let cached = cachedOrderedFrames {
            return cached
        }
        return computeOrderedFrames()
    }
    
    /// Computes ordered frames from content-space (for compatibility)
    private func computeOrderedFrames() -> [(item: Pinboard, frame: CGRect)] {
        pinboards.compactMap { pinboard in
            guard let frame = tabFrames[pinboard.objectID] else { return nil }
            return (item: pinboard, frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }
    
    /// Computes ordered frames from local-space (for drag and placeholder)
    private func computeLocalOrderedFrames() -> [(item: Pinboard, frame: CGRect)] {
        pinboards.compactMap { pinboard in
            guard let frame = localTabFrames[pinboard.objectID] else { return nil }
            return (item: pinboard, frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

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

    private func handleBlurCommit() {
        guard isCreating || editingID != nil else { return }

        DispatchQueue.main.async {
            if cancelRequested {
                cancelRequested = false
                return
            }
            if commitRequested {
                commitRequested = false
                return
            }
            if suppressNextBlurCommit {
                suppressNextBlurCommit = false
                return
            }
            
            // Only commit if the user clicked elsewhere in the active window.
            // If the window is not visible or not key, we assume the overlay is closing/inactive, so we cancel.
            if let window = NSApp.windows.first(where: { $0.isKeyWindow }), window.isVisible {
                onCommit()
            } else {
                onCancel()
            }
        }
    }

    private func handleCommitButton() {
        commitRequested = true
        onCommit()
        isFocused = false
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        if let dropTarget,
           let localFrame = localTabFrames[dropTarget.item.objectID] {
            let height = max(0, localFrame.height)
            // placeholderX is now calculated directly in local-space
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
           let localFrame = localTabFrames[draggedItem.objectID] {
            PinboardTabPreview(title: draggedItem.name, colorHex: draggedItem.colorHex)
                .frame(width: localFrame.width, height: localFrame.height)
                .position(
                    // Position at cursor minus the initial offset from cursor to center
                    x: dragState.pointerLocation.x - dragState.cursorOffset.width,
                    y: dragState.pointerLocation.y - dragState.cursorOffset.height
                )
                .opacity(dragOpacity)
                .animation(.easeOut(duration: 0.1), value: dragOpacity)
                .allowsHitTesting(false)
        }
    }
}

struct TabFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] = [:]

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct LocalTabFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] = [:]

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct PinboardFrameKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: CGRect] = [:]

    static func reduce(value: inout [NSManagedObjectID: CGRect], nextValue: () -> [NSManagedObjectID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct PinboardAllFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct PinboardEditorFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct DragState: Equatable {
    let itemID: NSManagedObjectID
    var pointerLocation: CGPoint
    // Local-space center for stable drag preview positioning
    let localBaseCenter: CGPoint
    // Content-space center for drop target calculations
    let contentBaseCenter: CGPoint
    // Scroll offset when drag started (frozen during drag)
    let initialScrollOffset: CGFloat
    var translation: CGSize
    // Offset from cursor to item center at drag start
    let cursorOffset: CGSize
    
    static func == (lhs: DragState, rhs: DragState) -> Bool {
        lhs.itemID == rhs.itemID &&
        lhs.pointerLocation == rhs.pointerLocation &&
        lhs.translation == rhs.translation
    }
}

private struct DropTarget: Equatable {
    let item: Pinboard
    let insertBefore: Bool
    let placeholderX: CGFloat

    static func == (lhs: DropTarget, rhs: DropTarget) -> Bool {
        lhs.item.objectID == rhs.item.objectID &&
            lhs.insertBefore == rhs.insertBefore &&
            lhs.placeholderX == rhs.placeholderX
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 20 // Default to scrollContentPadding
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Take the actual value from "All" tab (only item that reports)
        value = nextValue()
    }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
