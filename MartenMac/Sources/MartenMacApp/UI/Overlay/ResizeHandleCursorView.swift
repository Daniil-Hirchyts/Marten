import AppKit
import SwiftUI

struct ResizeHandleCursorView: NSViewRepresentable {
    let axis: OverlayLayoutAxis

    func makeNSView(context: Context) -> NSView {
        CursorRectView(axis: axis)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorRectView, view.axis != axis else { return }
        view.axis = axis
        view.discardCursorRects()
        view.resetCursorRects()
    }

    private final class CursorRectView: NSView {
        var axis: OverlayLayoutAxis
        private var sessionStateObserver: NSObjectProtocol?

        init(axis: OverlayLayoutAxis) {
            self.axis = axis
            super.init(frame: .zero)
            sessionStateObserver = NotificationCenter.default.addObserver(
                forName: OCRSelectionSessionState.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshCursorRects()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            if let sessionStateObserver {
                NotificationCenter.default.removeObserver(sessionStateObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshCursorRects()
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard !OCRSelectionSessionState.isActive else { return }
            let cursor: NSCursor = axis == .horizontal ? .resizeUpDown : .resizeLeftRight
            addCursorRect(bounds, cursor: cursor)
        }

        private func refreshCursorRects() {
            discardCursorRects()
            guard let window else { return }
            window.invalidateCursorRects(for: self)
        }
    }
}
