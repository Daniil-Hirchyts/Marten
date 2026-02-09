import CoreGraphics
import Foundation

public struct SelectionImageCropper: Sendable {
    public init() {}

    public func pixelRect(
        for selectionInDisplayPoints: CGRect,
        displaySizeInPoints: CGSize,
        scale: CGFloat,
        imageSizeInPixels: CGSize
    ) -> CGRect {
        let selection = selectionInDisplayPoints.standardized
        guard
            selection.width > 0,
            selection.height > 0,
            displaySizeInPoints.width > 0,
            displaySizeInPoints.height > 0
        else {
            return .null
        }

        let imageWidth = imageSizeInPixels.width
        let imageHeight = imageSizeInPixels.height

        // Prefer the real image-to-display ratio to handle scaled-display modes
        // where NSScreen.backingScaleFactor does not exactly match capture output.
        let fallbackScale = max(scale, 1)
        let computedXScale = imageWidth / displaySizeInPoints.width
        let computedYScale = imageHeight / displaySizeInPoints.height
        let xScale = computedXScale.isFinite && computedXScale > 0 ? computedXScale : fallbackScale
        let yScale = computedYScale.isFinite && computedYScale > 0 ? computedYScale : fallbackScale

        let minX = max(0, selection.minX * xScale)
        let maxX = min(imageWidth, selection.maxX * xScale)

        let minYFromBottom = max(0, selection.minY * yScale)
        let maxYFromBottom = min(imageHeight, selection.maxY * yScale)

        let minYFromTop = imageHeight - maxYFromBottom
        let maxYFromTop = imageHeight - minYFromBottom

        let clamped = CGRect(
            x: minX,
            y: minYFromTop,
            width: max(0, maxX - minX),
            height: max(0, maxYFromTop - minYFromTop)
        ).integral

        guard clamped.width > 0, clamped.height > 0 else {
            return .null
        }
        return clamped
    }

    public func crop(
        image: CGImage,
        selectionInDisplayPoints: CGRect,
        displaySizeInPoints: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let pixelRect = pixelRect(
            for: selectionInDisplayPoints,
            displaySizeInPoints: displaySizeInPoints,
            scale: scale,
            imageSizeInPixels: CGSize(width: image.width, height: image.height)
        )
        guard !pixelRect.isNull else { return nil }
        return image.cropping(to: pixelRect)
    }
}
