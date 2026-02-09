import CoreGraphics
import Foundation

struct OverlayFrameCalculationResult {
    let frame: CGRect
    let persistedSize: CGFloat
}

enum OverlayFrameCalculator {
    static let contentMargin: CGFloat = 8
    static let minimumRemainingScreenSpace: CGFloat = 50
    static let minimumHorizontalHeight: CGFloat = 220
    static let maximumHorizontalHeight: CGFloat = 400
    static let minimumVerticalWidth: CGFloat = 280
    static let maximumVerticalWidth: CGFloat = 620

    static func frame(
        visibleFrame: CGRect,
        edge: OverlayScreenEdge,
        preferredHorizontalSize: CGFloat,
        preferredVerticalSize: CGFloat
    ) -> CGRect {
        switch edge.layoutAxis {
        case .horizontal:
            let width = max(visibleFrame.width - (contentMargin * 2), 320)
            let height = clampedSize(
                preferred: preferredHorizontalSize,
                axis: .horizontal,
                visibleFrame: visibleFrame
            )
            let x = visibleFrame.minX + contentMargin
            let y: CGFloat
            switch edge {
            case .bottom:
                y = visibleFrame.minY + contentMargin
            case .top:
                y = visibleFrame.maxY - contentMargin - height
            case .left, .right:
                y = visibleFrame.minY + contentMargin
            }
            return CGRect(x: x, y: y, width: width, height: height)
        case .vertical:
            let width = clampedSize(
                preferred: preferredVerticalSize,
                axis: .vertical,
                visibleFrame: visibleFrame
            )
            let height = max(visibleFrame.height - (contentMargin * 2), minimumHorizontalHeight)
            let y = visibleFrame.minY + contentMargin
            let x: CGFloat
            switch edge {
            case .left:
                x = visibleFrame.minX + contentMargin
            case .right:
                x = visibleFrame.maxX - contentMargin - width
            case .bottom, .top:
                x = visibleFrame.minX + contentMargin
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    static func showOffset(for edge: OverlayScreenEdge) -> CGSize {
        switch edge {
        case .bottom:
            return CGSize(width: 0, height: -16)
        case .top:
            return CGSize(width: 0, height: 16)
        case .left:
            return CGSize(width: -16, height: 0)
        case .right:
            return CGSize(width: 16, height: 0)
        }
    }

    static func hideOffset(for edge: OverlayScreenEdge) -> CGSize {
        switch edge {
        case .bottom:
            return CGSize(width: 0, height: -8)
        case .top:
            return CGSize(width: 0, height: 8)
        case .left:
            return CGSize(width: -8, height: 0)
        case .right:
            return CGSize(width: 8, height: 0)
        }
    }

    static func clampedSize(
        preferred: CGFloat,
        axis: OverlayLayoutAxis,
        visibleFrame: CGRect
    ) -> CGFloat {
        switch axis {
        case .horizontal:
            let maxAllowed = min(
                visibleFrame.height - minimumRemainingScreenSpace,
                maximumHorizontalHeight
            )
            return min(max(minimumHorizontalHeight, preferred), maxAllowed)
        case .vertical:
            let maxAllowed = min(
                visibleFrame.width - minimumRemainingScreenSpace,
                maximumVerticalWidth
            )
            return min(max(minimumVerticalWidth, preferred), maxAllowed)
        }
    }

    static func resizedFrame(
        from anchorFrame: CGRect,
        visibleFrame: CGRect,
        edge: OverlayScreenEdge,
        proposedEdgePosition: CGFloat
    ) -> OverlayFrameCalculationResult {
        switch edge {
        case .bottom:
            let minTop = anchorFrame.minY + minimumHorizontalHeight
            let maxTop = anchorFrame.minY + clampedSize(
                preferred: CGFloat.greatestFiniteMagnitude,
                axis: .horizontal,
                visibleFrame: visibleFrame
            )
            let clampedTop = min(max(minTop, proposedEdgePosition), maxTop)
            let height = clampedTop - anchorFrame.minY
            var frame = anchorFrame
            frame.size.height = height
            return OverlayFrameCalculationResult(frame: frame, persistedSize: height)
        case .top:
            let maxBottom = anchorFrame.maxY - minimumHorizontalHeight
            let minBottom = anchorFrame.maxY - clampedSize(
                preferred: CGFloat.greatestFiniteMagnitude,
                axis: .horizontal,
                visibleFrame: visibleFrame
            )
            let clampedBottom = min(max(minBottom, proposedEdgePosition), maxBottom)
            let height = anchorFrame.maxY - clampedBottom
            let frame = CGRect(
                x: anchorFrame.minX,
                y: clampedBottom,
                width: anchorFrame.width,
                height: height
            )
            return OverlayFrameCalculationResult(frame: frame, persistedSize: height)
        case .left:
            let minRight = anchorFrame.minX + minimumVerticalWidth
            let maxRight = anchorFrame.minX + clampedSize(
                preferred: CGFloat.greatestFiniteMagnitude,
                axis: .vertical,
                visibleFrame: visibleFrame
            )
            let clampedRight = min(max(minRight, proposedEdgePosition), maxRight)
            let width = clampedRight - anchorFrame.minX
            var frame = anchorFrame
            frame.size.width = width
            return OverlayFrameCalculationResult(frame: frame, persistedSize: width)
        case .right:
            let maxLeft = anchorFrame.maxX - minimumVerticalWidth
            let minLeft = anchorFrame.maxX - clampedSize(
                preferred: CGFloat.greatestFiniteMagnitude,
                axis: .vertical,
                visibleFrame: visibleFrame
            )
            let clampedLeft = min(max(minLeft, proposedEdgePosition), maxLeft)
            let width = anchorFrame.maxX - clampedLeft
            let frame = CGRect(
                x: clampedLeft,
                y: anchorFrame.minY,
                width: width,
                height: anchorFrame.height
            )
            return OverlayFrameCalculationResult(frame: frame, persistedSize: width)
        }
    }
}
