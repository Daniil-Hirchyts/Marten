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
                        ItemCardDragPreview(item: item, pinboards: data.pinboards, cardSize: data.cardSize)
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

// MARK: - Pinboard Drag Preview Window

/// Data for pinboard tab drag preview
struct PinboardDragPreviewData: Equatable {
    let title: String
    let colorHex: String?
    let size: CGSize
    let opacity: Double
}

/// A separate borderless window that displays pinboard tab drag preview outside the main overlay bounds
class PinboardDragPreviewWindow: NSWindow {
    private var hostingView: NSHostingView<PinboardDragPreviewWindowContent>?

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

        let rootView = PinboardDragPreviewWindowContent(data: nil)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 300, height: 100))
        self.contentView = hosting
        self.hostingView = hosting

        self.setFrame(NSRect(origin: .zero, size: NSSize(width: 300, height: 100)), display: false)
    }

    func updatePreview(_ data: PinboardDragPreviewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = PinboardDragPreviewWindowContent(data: data)

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

private struct PinboardDragPreviewWindowContent: View {
    let data: PinboardDragPreviewData?

    var body: some View {
        ZStack {
            if let data = data {
                GeometryReader { _ in
                    PinboardTabPreviewView(title: data.title, colorHex: data.colorHex)
                        .frame(width: data.size.width, height: data.size.height)
                        .position(x: 150, y: 50) // Center of the 300x100 window
                        .opacity(data.opacity)
                        .animation(.easeOut(duration: 0.06), value: data.opacity)
                }
            }
        }
        .frame(width: 300, height: 100)
        .allowsHitTesting(false)
    }
}

/// Standalone pinboard tab preview for the drag window
private struct PinboardTabPreviewView: View {
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
                    (colorScheme == .dark ? Color.white : Color.black).opacity(0.3)
                }
            }
        )
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}

