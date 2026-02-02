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
    @State private var isDragging = false

    @State private var anchorY: CGFloat = 0
    @State private var clickOffsetY: CGFloat = 0

    var body: some View {
        VStack {
            ZStack {
                ResizeHandleCursorView()
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .accessibilityIdentifier("overlay.resizeHandle")
            .accessibilityLabel("Resize overlay")
            .accessibilityHint("Drag up or down to resize")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard let window = window else { return }

                        if !isDragging {
                            isDragging = true
                            anchorY = window.frame.minY

                            let currentTopY = window.frame.maxY
                            let mouseScreenY = NSEvent.mouseLocation.y
                            clickOffsetY = currentTopY - mouseScreenY
                        }

                        let mouseScreenY = NSEvent.mouseLocation.y
                        let targetTopY = mouseScreenY + clickOffsetY
                        let newHeight = targetTopY - anchorY

                        let screenHeight = window.screen?.visibleFrame.height ?? 800
                        let maxHeight = min(screenHeight - 50, 400)
                        let minHeight: CGFloat = 220
                        let clamped = min(max(minHeight, newHeight), maxHeight)

                        var frame = window.frame
                        if frame.size.height != clamped {
                            frame.size.height = clamped
                            window.setFrame(frame, display: true)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        if let window = window {
                            let height = window.frame.height
                            UserDefaults.standard.set(height, forKey: "OverlayHeight")
                            UserDefaults.standard.synchronize()
                            Logger.ui.info("Saved overlay height: \(height, privacy: .public)")
                        }
                    }
            )
            Spacer()
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
    func makeNSView(context: Context) -> NSView {
        CursorRectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CursorRectView: NSView {
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }
}
