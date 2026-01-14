import AppKit
import ClipboardCore
import SwiftUI

/// A separate borderless window that displays drag preview outside the main overlay bounds
class DragPreviewWindow: NSWindow {
    private var hostingView: NSHostingView<DragPreviewWindowContent>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = DragPreviewWindowContent(data: nil)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 600))
        self.contentView = hosting
        self.hostingView = hosting

        self.setFrame(NSRect(origin: .zero, size: NSSize(width: 600, height: 600)), display: false)
    }

    func updatePreview(_ data: DragPreviewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = DragPreviewWindowContent(data: data)

        if data != nil {
            if !self.isVisible {
                self.orderFront(nil)
            }
        } else {
            if self.isVisible {
                self.orderOut(nil)
            }
        }
    }
}

private struct DragPreviewWindowContent: View {
    let data: DragPreviewData?

    var body: some View {
        ZStack {
            if let data = data {
                GeometryReader { _ in
                    if data.items.count == 1, let item = data.items.first {
                        ItemCardDragPreview(item: item, pinboards: data.pinboards)
                            .frame(width: data.cardSize, height: data.cardSize)
                            .position(x: 300, y: 300) // Center of the 600x600 window
                            .opacity(data.opacity)
                            .animation(.easeOut(duration: 0.06), value: data.opacity)
                    } else if data.items.count > 1 {
                        MultiItemCardDragPreview(
                            items: data.items,
                            pinboards: data.pinboards,
                            cardSize: data.cardSize
                        )
                        .position(x: 300, y: 300)
                        .opacity(data.opacity)
                        .animation(.easeOut(duration: 0.06), value: data.opacity)
                    }
                }
            }
        }
        .frame(width: 600, height: 600)
        .allowsHitTesting(false)
    }
}
