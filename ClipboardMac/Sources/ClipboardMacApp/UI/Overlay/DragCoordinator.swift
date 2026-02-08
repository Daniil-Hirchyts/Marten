import AppKit
import ClipboardCore
import CoreData
import SwiftUI

@MainActor
final class DragCoordinator: ObservableObject {
    @Published var pinboardFrames: [NSManagedObjectID: CGRect] = [:]
    @Published var allPinboardFrame: CGRect?
    @Published var pinboardEditorFrame: CGRect?
    var searchFieldFrame: CGRect?
    @Published var dragPreviewData: DragPreviewData?
    @Published var pinboardDragPreviewData: PinboardDragPreviewData?

    private var dragPreviewWindow: DragPreviewWindow?
    private var pinboardDragPreviewWindow: PinboardDragPreviewWindow?
    private let nativeDragSource = NativeDragSource()
    private(set) var isNativeDragActive = false

    func updatePinboardLayout(_ layout: PinboardLayoutInfo) {
        guard dragPreviewData == nil else { return }

        if !framesApproximatelyEqual(layout.overlayPinboardFrames, pinboardFrames) {
            pinboardFrames = layout.overlayPinboardFrames
        }
        if !rectsApproximatelyEqual(layout.allOverlayFrame, allPinboardFrame) {
            allPinboardFrame = layout.allOverlayFrame
        }
        if !rectsApproximatelyEqual(layout.editorOverlayFrame, pinboardEditorFrame) {
            pinboardEditorFrame = layout.editorOverlayFrame
        }
    }

    func updateSearchFieldFrame(_ frame: CGRect?) {
        guard dragPreviewData == nil else { return }
        if !rectsApproximatelyEqual(frame, searchFieldFrame) {
            searchFieldFrame = frame
        }
    }

    func clearPinboardLayoutState() {
        pinboardFrames = [:]
        allPinboardFrame = nil
        pinboardEditorFrame = nil
    }

    func ensurePreviewWindow() {
        if dragPreviewWindow == nil {
            dragPreviewWindow = DragPreviewWindow()
        }
    }

    func ensurePinboardPreviewWindow() {
        if pinboardDragPreviewWindow == nil {
            pinboardDragPreviewWindow = PinboardDragPreviewWindow()
        }
    }

    func cleanupPreviewWindow() {
        dragPreviewWindow?.close()
        dragPreviewWindow = nil
        dragPreviewData = nil
    }

    func cleanupPinboardPreviewWindow() {
        pinboardDragPreviewWindow?.close()
        pinboardDragPreviewWindow = nil
        pinboardDragPreviewData = nil
    }

    func updateDragPreviewWindow(_ data: DragPreviewData?, parentWindow: NSWindow?) {
        guard parentWindow != nil else { return }
        // Don't recreate the preview window while a native drag session owns the visuals
        guard !isNativeDragActive else { return }

        if let data {
            // Create a fresh preview window each time the drag starts (window not yet visible)
            // to avoid a flash of stale content from a previous drag.
            if dragPreviewWindow == nil || !dragPreviewWindow!.isVisible {
                dragPreviewWindow?.close()
                dragPreviewWindow = DragPreviewWindow()
            }

            let mouseLocation = NSEvent.mouseLocation
            let previewFrame = NSRect(
                x: mouseLocation.x - 300,
                y: mouseLocation.y - 300,
                width: 600,
                height: 600
            )

            dragPreviewWindow!.setFrame(previewFrame, display: false)
            dragPreviewWindow!.updatePreview(data)
        } else {
            dragPreviewWindow?.updatePreview(nil)
        }
    }

    func updatePinboardDragPreviewWindow(_ data: PinboardDragPreviewData?, parentWindow: NSWindow?) {
        guard let pinboardDragPreviewWindow, parentWindow != nil else { return }

        if let data {
            let mouseLocation = NSEvent.mouseLocation
            let previewFrame = NSRect(
                x: mouseLocation.x - 150,
                y: mouseLocation.y - 50,
                width: 300,
                height: 100
            )

            pinboardDragPreviewWindow.setFrame(previewFrame, display: false)
            pinboardDragPreviewWindow.updatePreview(data)
        } else {
            pinboardDragPreviewWindow.updatePreview(nil)
        }
    }

    // MARK: - Native Drag

    /// Start a native drag session when items are dragged outside the overlay.
    ///
    /// - Returns: `true` if the native session started successfully.
    func beginNativeDrag(
        from window: NSWindow?,
        items: [ClipItem],
        plainText: Bool,
        onCompleted: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) -> Bool {
        guard let contentView = window?.contentView else { return false }

        // Capture the drag preview image (cropped to card area) before hiding the preview window
        let dragImage = dragPreviewWindow?.capturePreviewImage(data: dragPreviewData)

        // Hide the SwiftUI drag preview
        cleanupPreviewWindow()

        let screenPoint = NSEvent.mouseLocation

        isNativeDragActive = true

        let started = nativeDragSource.beginSession(
            from: contentView,
            at: screenPoint,
            items: items,
            plainText: plainText,
            dragImage: dragImage,
            onCompleted: onCompleted,
            onEnded: { [weak self] in
                self?.isNativeDragActive = false
                onEnded()
            }
        )

        if !started {
            isNativeDragActive = false
        }

        return started
    }
}
