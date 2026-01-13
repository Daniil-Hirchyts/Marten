import ClipboardCore
import CoreData
import SwiftUI

struct PinboardTabBar: View {
    private let tabSpacing: CGFloat = 12
    private let placeholderWidth: CGFloat = 3
    private let localCoordinateSpaceName = "PinboardBarLocalSpace"
    private let createFieldWidth: CGFloat = 200

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

    private var canReorder: Bool {
        editingID == nil && !isCreating
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                let placeholderInset = (tabSpacing / 2) + (placeholderWidth / 2)
                HStack(spacing: tabSpacing) {
                    PinboardTab(title: "All", colorHex: nil, isSelected: selectedID == nil, minWidth: 60) {
                        onSelect(nil)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PinboardAllFrameKey.self,
                                value: proxy.frame(in: .named(coordinateSpaceName))
                            )
                        }
                    )

                    ForEach(Array(pinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                        if editingID == pinboard.objectID {
                            editingView(pinboard: pinboard)
                        } else {
                            pinboardView(pinboard: pinboard, index: index)
                        }
                    }

                    ZStack(alignment: .leading) {
                        if isCreating {
                            createView()
                        } else {
                            Button(action: onCreate) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(8)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: createFieldWidth, alignment: .leading)
                }
                .padding(.horizontal, placeholderInset)
                .frame(minWidth: proxy.size.width)
            }
        }
        .coordinateSpace(name: localCoordinateSpaceName)
        .overlay(alignment: .topLeading) {
            placeholderView()
        }
        .overlay(alignment: .topLeading) {
            dragPreviewView()
        }
        .onPreferenceChange(TabFrameKey.self) { frames in
            tabFrames = frames
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
                if draftName.isEmpty {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
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
                .onAppear { isFocused = true }
            }
            .frame(minWidth: 70)
            .layoutPriority(1)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
        .frame(width: 140)
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
                if draftName.isEmpty {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
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
                .onAppear { isFocused = true }
            }
            .frame(minWidth: 90)
            .layoutPriority(1)

            Button(action: handleCommitButton) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button(action: handleCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func pinboardView(pinboard: Pinboard, index: Int) -> some View {
        let isDragging = dragState?.itemID == pinboard.objectID

        let base = PinboardTab(title: pinboard.name, colorHex: pinboard.colorHex, isSelected: selectedID == pinboard.id) {
            onSelect(pinboard.id)
        }
        .opacity(isDragging ? 0.25 : 1)
        .background(
            GeometryReader { proxy in
                let localFrame = proxy.frame(in: .named(localCoordinateSpaceName))
                let overlayFrame = proxy.frame(in: .named(coordinateSpaceName))
                Color.clear
                    .preference(key: TabFrameKey.self, value: [pinboard.objectID: localFrame])
                    .preference(key: PinboardFrameKey.self, value: [pinboard.objectID: overlayFrame])
            }
        )
        .fixedSize(horizontal: true, vertical: false)
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
            onCommit()
        }
    }

    private func handleCancel() {
        cancelRequested = true
        onCancel()
        isFocused = false
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
                    x: dragState.baseCenter.x + dragState.translation.width,
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
                .fixedSize()
        }
        .frame(minHeight: 20)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.2))
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}
