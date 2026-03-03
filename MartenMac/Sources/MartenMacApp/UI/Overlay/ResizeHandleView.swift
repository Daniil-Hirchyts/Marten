import AppKit
import OSLog
import SwiftUI

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
                
                let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
                let proposedPosition = proposedEdgePosition(for: edge, pointerOffset: clickOffset)
                let result = OverlayFrameCalculator.resizedFrame(
                    from: anchorFrame,
                    visibleFrame: visibleFrame,
                    edge: edge,
                    proposedEdgePosition: proposedPosition
                )
                
                let axis = edge.layoutAxis
                let size = result.persistedSize
                OverlayLayoutSettings().setPersistedSize(size, for: axis)
                Logger.ui.info("Saved overlay size: \(size, privacy: .public) axis=\(axis.rawValue, privacy: .public)")

                if !rectsApproximatelyEqual(window.frame, result.clampedFrame, tolerance: 0.5) {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        window.animator().setFrame(result.clampedFrame, display: true)
                    }
                }
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
