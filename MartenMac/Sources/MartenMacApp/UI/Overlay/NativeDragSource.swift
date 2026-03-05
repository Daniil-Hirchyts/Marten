import AppKit
import MartenCore
import MartenMacServices

/// Manages native `NSDraggingSession` for dragging clipboard items to external apps.
///
/// When a card is dragged outside the overlay window, this source initiates a real macOS
/// drag session so target applications see native drag events and can update their
/// insertion carets accordingly.
@MainActor
final class NativeDragSource: NSObject, NSDraggingSource, @unchecked Sendable {

    private var onSessionEnded: (() -> Void)?
    private var onDragCompleted: (() -> Void)?
    private var draggingSession: NSDraggingSession?

    // MARK: - NSDraggingSource

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy]
        case .withinApplication:
            return []
        @unknown default:
            return [.copy]
        }
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // AppKit delivers this callback on the main thread, but use async
        // dispatch to avoid crashing if the runtime isolation check fails.
        DispatchQueue.main.async { [self] in
            if operation != [] {
                onDragCompleted?()
            }
            onSessionEnded?()
            onSessionEnded = nil
            onDragCompleted = nil
            draggingSession = nil
        }
    }

    // MARK: - Session Start

    /// Start a native drag session from the given view.
    ///
    /// - Parameters:
    ///   - view: The NSView to initiate the session from (typically the overlay panel's content view).
    ///   - screenPoint: Current mouse location in screen coordinates.
    ///   - items: The clipboard items to drag.
    ///   - plainText: Whether to provide only plain text content.
    ///   - dragImage: Optional image to display during the drag.
    ///   - onCompleted: Called when the content is successfully dropped.
    ///   - onEnded: Called when the drag session ends (success or cancel).
    /// - Returns: `true` if the session started successfully.
    func beginSession(
        from view: NSView,
        at screenPoint: NSPoint,
        items: [ClipItem],
        plainText: Bool,
        dragImage: NSImage?,
        onCompleted: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) -> Bool {
        let draggingItems = makeDraggingItems(from: items, plainText: plainText)
        guard !draggingItems.isEmpty else { return false }

        let windowPoint = view.window?.convertPoint(fromScreen: screenPoint) ?? screenPoint
        let viewPoint = view.convert(windowPoint, from: nil)
        let clampedViewPoint = clamp(point: viewPoint, to: view.bounds)
        let eventLocation = view.convert(clampedViewPoint, to: nil)

        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: eventLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ) else { return false }

        let effectiveImage = dragImage ?? makeFallbackDragImage()
        let imageSize = effectiveImage.size

        for (index, draggingItem) in draggingItems.enumerated() {
            draggingItem.setDraggingFrame(
                NSRect(
                    x: clampedViewPoint.x - imageSize.width / 2,
                    y: clampedViewPoint.y - imageSize.height / 2,
                    width: imageSize.width,
                    height: imageSize.height
                ),
                contents: index == 0 ? effectiveImage : nil
            )
        }

        self.onSessionEnded = onEnded
        self.onDragCompleted = onCompleted

        let session = view.beginDraggingSession(
            with: draggingItems,
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
        self.draggingSession = session

        return true
    }

    // MARK: - Private

    private func makeDraggingItems(from items: [ClipItem], plainText: Bool) -> [NSDraggingItem] {
        let builder = PasteboardItemBuilder()

        return items.compactMap { item in
            let pasteboardItem: NSPasteboardItem?
            if plainText {
                pasteboardItem = builder.buildPlainTextPasteboardItem(from: item)
            } else {
                pasteboardItem = try? builder.buildPasteboardItem(from: item)
            }
            guard let pasteboardItem else { return nil }
            return NSDraggingItem(pasteboardWriter: pasteboardItem)
        }
    }

    private func makeFallbackDragImage() -> NSImage {
        let size = NSSize(width: 160, height: 40)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        image.unlockFocus()
        return image
    }

    private func clamp(point: CGPoint, to bounds: CGRect) -> CGPoint {
        guard !bounds.isEmpty else { return point }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
