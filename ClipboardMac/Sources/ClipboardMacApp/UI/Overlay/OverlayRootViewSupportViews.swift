import AppKit
import ClipboardCore
import OSLog
import SwiftUI

struct SearchFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@available(macOS 14.0, *)
struct OverlaySettingsButton14: View {
    let closeOverlay: (@escaping () -> Void) -> Void
    let label: AnyView

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            closeOverlay {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
        } label: {
            label
        }
    }
}

struct RenameOverlayView: View {
    @Binding var title: String
    var onSave: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Item")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit {
                    onSave()
                }
                .accessibilityIdentifier("overlay.rename.title")
                .accessibilityLabel("Title")
                .accessibilityValue(title.isEmpty ? "Empty" : title)
                .accessibilityHint("Enter a new title")

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overlay.rename.cancel")
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses without saving")

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("overlay.rename.save")
                .accessibilityLabel("Save")
                .accessibilityHint("Saves the new title")
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

struct ResizeHandleView: View {
    let window: NSWindow?
    @AppStorage(OverlayLayoutSettings.Keys.overlayScreenEdge)
    private var overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue

    @State private var isDragging = false
    @State private var anchorFrame: CGRect = .zero
    @State private var clickOffset: CGFloat = 0

    private var edge: OverlayScreenEdge {
        OverlayScreenEdge(rawValue: overlayScreenEdgeRawValue) ?? OverlayLayoutSettings.defaultEdge
    }

    var body: some View {
        Group {
            switch edge {
            case .bottom:
                VStack(spacing: 0) {
                    horizontalHandle
                    Spacer(minLength: 0)
                }
            case .top:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    horizontalHandle
                }
            case .left:
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    verticalHandle
                }
            case .right:
                HStack(spacing: 0) {
                    verticalHandle
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var horizontalHandle: some View {
        ZStack {
            ResizeHandleCursorView(axis: .horizontal)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .accessibilityIdentifier("overlay.resizeHandle")
        .accessibilityLabel("Resize overlay")
        .accessibilityHint("Drag to resize")
        .gesture(resizeGesture)
    }

    private var verticalHandle: some View {
        ZStack {
            ResizeHandleCursorView(axis: .vertical)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .accessibilityIdentifier("overlay.resizeHandle")
        .accessibilityLabel("Resize overlay")
        .accessibilityHint("Drag to resize")
        .gesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard let window else { return }

                if !isDragging {
                    isDragging = true
                    anchorFrame = window.frame
                    clickOffset = initialPointerOffset(for: edge, frame: anchorFrame)
                }

                let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
                let proposedPosition = proposedEdgePosition(for: edge, pointerOffset: clickOffset)
                let result = OverlayFrameCalculator.resizedFrame(
                    from: anchorFrame,
                    visibleFrame: visibleFrame,
                    edge: edge,
                    proposedEdgePosition: proposedPosition
                )
                if !rectsApproximatelyEqual(window.frame, result.frame, tolerance: 0.5) {
                    window.setFrame(result.frame, display: true)
                }
            }
            .onEnded { _ in
                isDragging = false
                guard let window else { return }
                let axis = edge.layoutAxis
                let size = axis == .horizontal ? window.frame.height : window.frame.width
                OverlayLayoutSettings().setPersistedSize(size, for: axis)
                Logger.ui.info("Saved overlay size: \(size, privacy: .public) axis=\(axis.rawValue, privacy: .public)")
            }
    }

    private func initialPointerOffset(for edge: OverlayScreenEdge, frame: CGRect) -> CGFloat {
        let location = NSEvent.mouseLocation
        switch edge {
        case .bottom:
            return frame.maxY - location.y
        case .top:
            return frame.minY - location.y
        case .left:
            return frame.maxX - location.x
        case .right:
            return frame.minX - location.x
        }
    }

    private func proposedEdgePosition(for edge: OverlayScreenEdge, pointerOffset: CGFloat) -> CGFloat {
        let location = NSEvent.mouseLocation
        switch edge {
        case .bottom, .top:
            return location.y + pointerOffset
        case .left, .right:
            return location.x + pointerOffset
        }
    }
}

@MainActor
final class ReturnKeyHandler {
    weak var viewModel: OverlayViewModel?
    weak var modifierMonitor: ModifierKeyMonitor?
    let getFilteredItems: () -> [ClipItem]

    init(
        viewModel: OverlayViewModel,
        modifierMonitor: ModifierKeyMonitor,
        getFilteredItems: @escaping () -> [ClipItem]
    ) {
        self.viewModel = viewModel
        self.modifierMonitor = modifierMonitor
        self.getFilteredItems = getFilteredItems
    }

    func handleReturnKey() {
        guard let viewModel = viewModel, let modifierMonitor = modifierMonitor else { return }
        viewModel.handleReturnKey(
            orderedItems: getFilteredItems(),
            isShiftPressed: modifierMonitor.isShiftPressed
        )
    }
}

struct ResizeHandleCursorView: NSViewRepresentable {
    let axis: OverlayLayoutAxis

    func makeNSView(context: Context) -> NSView {
        CursorRectView(axis: axis)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorRectView else { return }
        view.axis = axis
        view.discardCursorRects()
        view.resetCursorRects()
    }

    private final class CursorRectView: NSView {
        var axis: OverlayLayoutAxis

        init(axis: OverlayLayoutAxis) {
            self.axis = axis
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            let cursor: NSCursor = axis == .horizontal ? .resizeUpDown : .resizeLeftRight
            addCursorRect(bounds, cursor: cursor)
        }
    }
}
