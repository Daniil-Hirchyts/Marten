import ClipboardCore
import CoreData
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
    @State private var tabFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var dragState: DragState?
    @State private var dragOpacity: Double = 0
    @State private var dropTarget: DropTarget?
    @State private var cancelRequested = false
    @State private var commitRequested = false
    @State private var suppressNextBlurCommit = false
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var trailingTabWidth: CGFloat = 40 // Default or estimated
    @State private var isScrolled = false

    private let contentSpaceName = "PinboardContentSpace"
    private var canReorder: Bool {
        editingID == nil && !isCreating
    }

    private let maxScrollableWidthRatio: CGFloat = 0.85 // Maximum width as percentage of overlay width
    private let estimatedTabWidth: CGFloat = 90 // Estimated average tab width
    private let scrollContentPadding: CGFloat = 20 // Padding on each side inside scroll
    
    // Computed property for estimated content width based on number of pinboards (including All)
    private var estimatedContentWidth: CGFloat {
        let count = CGFloat(pinboards.count + 1) // +1 for "All" tab
        if count == 0 { return 0 }
        return (count * estimatedTabWidth) + ((count - 1) * tabSpacing)
    }
    
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: tabSpacing) {
                // Scrollable Pinboards (including "All" tab) - adapts to content width up to max
                ScrollView(.horizontal, showsIndicators: false) {
                    pinboardsContent(isMeasuring: false)
                        .padding(.horizontal, scrollContentPadding) // Extra padding so first item clears the blur zone
                        .coordinateSpace(name: contentSpaceName)
                }
                .coordinateSpace(name: scrollSpaceName)
                .frame(width: {
                    let maxScrollableWidth = proxy.size.width * maxScrollableWidthRatio
                    let availableWidth = max(0, proxy.size.width - trailingTabWidth - tabSpacing)
                    // Use actual measured width if available, otherwise estimate
                    let effectiveContentWidth = contentWidth > 0 ? contentWidth : estimatedContentWidth
                    // Add padding to content width, cap at max, and don't exceed available space
                    return min(effectiveContentWidth + (scrollContentPadding * 2), maxScrollableWidth, availableWidth)
                }())
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: !isScrolled ? [
                            // At initial position: only fade trailing edge
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.975),
                            .init(color: .clear, location: 1)
                        ] : [
                            // When scrolled: fade both edges (shorter blur zone)
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.025),
                            .init(color: .black, location: 0.975),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .animation(.easeOut(duration: 0.2), value: isScrolled)
                )

                // Fixed Creation View
                ZStack(alignment: .leading) {
                    if isCreating {
                        createView()
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
            tabFrames = frames
            // Calculate actual content width from tab frames
            if !frames.isEmpty {
                let minX = frames.values.map { $0.minX }.min() ?? 0
                let maxX = frames.values.map { $0.maxX }.max() ?? 0
                let measuredWidth = maxX - minX
                if measuredWidth > 0 {
                    contentWidth = measuredWidth
                }
            }
        }
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            isScrolled = offset < 15
            scrollOffset = offset
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
                        let localFrame = proxy.frame(in: .named(contentSpaceName))
                        let overlayFrame = proxy.frame(in: .named(coordinateSpaceName))
                        let minX = proxy.frame(in: .named(scrollSpaceName)).minX
                        
                        Color.clear
                            .preference(key: TabFrameKey.self, value: [NSManagedObjectID(): localFrame]) // Use empty ID for "All"
                            .preference(key: PinboardAllFrameKey.self, value: overlayFrame) // For drag/drop to All
                            .preference(key: ScrollOffsetKey.self, value: minX) // First item reports scroll offset
                    }
                }
            )
            
            // Other pinboards
            ForEach(Array(pinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                if editingID == pinboard.objectID {
                    editingView(pinboard: pinboard)
                } else {
                    pinboardView(pinboard: pinboard, index: index + 1, isMeasuring: isMeasuring) // +1 because "All" is index 0
                }
            }
        }
    }

    @ViewBuilder
    private func editingView(pinboard: Pinboard) -> some View {
        HStack(spacing: 6) {
            ColorPicker(selectedHex: pinboard.colorHex) { newColor in
                draftColor = newColor
                onColorChange(pinboard, newColor)
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
    private func createView() -> some View {
        HStack(spacing: 6) {
            ColorPicker(selectedHex: draftColor) { newColor in
                draftColor = newColor
                DispatchQueue.main.async {
                    isFocused = true
                }
                suppressNextBlurCommit = true
            }

            ZStack(alignment: .leading) {
                // Auto-sizing hidden text for dynamic width
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
                // Ensure focus works reliably
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
                      let contentFrame = proxy.frame(in: .named(contentSpaceName))
                      let overlayFrame = proxy.frame(in: .named(coordinateSpaceName))
                      let minX = proxy.frame(in: .named(scrollSpaceName)).minX
                      
                      Color.clear
                         .preference(key: TabFrameKey.self, value: [pinboard.objectID: contentFrame])
                         .preference(key: PinboardFrameKey.self, value: [pinboard.objectID: overlayFrame])
                         .preference(key: ScrollOffsetKey.self, value: index == 0 ? minX : 0) // Only first item reports scroll offset
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
        DragGesture(minimumDistance: 2, coordinateSpace: .named(contentSpaceName))
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

        if dragState == nil {
            guard let frame = tabFrames[pinboard.objectID] else { return }
            dragState = DragState(
                itemID: pinboard.objectID,
                pointerLocation: CGPoint(
                    x: value.startLocation.x + value.translation.width,
                    y: value.startLocation.y + value.translation.height
                ),
                baseCenter: CGPoint(x: frame.midX, y: frame.midY),
                translation: .zero
            )
            dragOpacity = 1
        } else if var state = dragState {
            state.pointerLocation = CGPoint(
                x: value.startLocation.x + value.translation.width,
                y: value.startLocation.y + value.translation.height
            )
            state.translation = value.translation
            dragState = state
        }

        let target = computeDropTarget(location: dragState?.pointerLocation ?? value.location, draggedID: pinboard.objectID)
        withAnimation(.easeOut(duration: 0.06)) {
            dropTarget = target
        }
    }

    private func handleDragEnded(pinboard: Pinboard, value: DragGesture.Value) {
        guard canReorder,
              let dragState,
              dragState.itemID == pinboard.objectID else {
            return
        }

        if let target = computeDropTarget(location: dragState.pointerLocation, draggedID: dragState.itemID),
           let draggedItem = pinboards.first(where: { $0.objectID == dragState.itemID }) {
            onReorder(draggedItem, target.item, target.insertBefore)
            onReorderEnd()
        }

        endDrag(for: dragState.itemID)
    }

    private func endDrag(for itemID: NSManagedObjectID) {
        withAnimation(.easeOut(duration: 0.06)) {
            dropTarget = nil
            dragOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if dragState?.itemID == itemID {
                dragState = nil
            }
        }
    }

    private func computeDropTarget(location: CGPoint, draggedID: NSManagedObjectID) -> DropTarget? {
        let ordered = orderedFrames()
        guard let draggedIndex = ordered.firstIndex(where: { $0.item.objectID == draggedID }),
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

        guard let candidate,
              let targetIndex = ordered.firstIndex(where: { $0.item.objectID == candidate.item.objectID }),
              !isNoOp(draggedIndex: draggedIndex, targetIndex: targetIndex, insertBefore: candidate.insertBefore) else {
            return nil
        }

        return candidate
    }

    private func placeholderX(for ordered: [(item: Pinboard, frame: CGRect)], targetIndex: Int, insertBefore: Bool) -> CGFloat {
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

    private func orderedFrames() -> [(item: Pinboard, frame: CGRect)] {
        pinboards.compactMap { pinboard in
            guard let frame = tabFrames[pinboard.objectID] else { return nil }
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
        if let dropTarget, let frame = tabFrames[dropTarget.item.objectID] {
            let height = max(0, frame.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.5))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 0)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.06), value: dropTarget)
        }
    }

    @ViewBuilder
    private func dragPreviewView() -> some View {
        if let dragState,
           let draggedItem = pinboards.first(where: { $0.objectID == dragState.itemID }) {
            PinboardTabPreview(title: draggedItem.name, colorHex: draggedItem.colorHex)
                .frame(width: tabFrames[draggedItem.objectID]?.width ?? 0,
                       height: tabFrames[draggedItem.objectID]?.height ?? 0)
                .position(
                    x: dragState.baseCenter.x + dragState.translation.width + scrollOffset,
                    y: dragState.baseCenter.y + dragState.translation.height
                )
                .opacity(dragOpacity)
                .animation(.easeOut(duration: 0.06), value: dragOpacity)
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

private struct DragState {
    let itemID: NSManagedObjectID
    var pointerLocation: CGPoint
    let baseCenter: CGPoint
    var translation: CGSize
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
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
