import AppKit
import CoreData
import SwiftUI

@MainActor
final class DragCoordinator: ObservableObject {
    @Published var pinboardFrames: [NSManagedObjectID: CGRect] = [:]
    @Published var allPinboardFrame: CGRect?
    @Published var pinboardEditorFrame: CGRect?
    @Published var searchFieldFrame: CGRect?
    @Published var dragPreviewData: DragPreviewData?

    private var dragPreviewWindow: DragPreviewWindow?

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

    func ensurePreviewWindow() {
        if dragPreviewWindow == nil {
            dragPreviewWindow = DragPreviewWindow()
        }
    }

    func cleanupPreviewWindow() {
        dragPreviewWindow?.orderOut(nil)
        dragPreviewWindow = nil
        dragPreviewData = nil
    }

    func updateDragPreviewWindow(_ data: DragPreviewData?, parentWindow: NSWindow?) {
        guard let dragPreviewWindow, parentWindow != nil else { return }

        if let data {
            let mouseLocation = NSEvent.mouseLocation
            let previewFrame = NSRect(
                x: mouseLocation.x - 300,
                y: mouseLocation.y - 300,
                width: 600,
                height: 600
            )

            dragPreviewWindow.setFrame(previewFrame, display: false)
            dragPreviewWindow.updatePreview(data)
        } else {
            dragPreviewWindow.updatePreview(nil)
        }
    }
}

