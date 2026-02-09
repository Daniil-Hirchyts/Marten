import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

public protocol ScreenImageCapturing {
    func captureDisplay(displayID: CGDirectDisplayID) -> CGImage?
    func captureRegion(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        displaySizeInPoints: CGSize,
        scale: CGFloat
    ) -> CGImage?
}

public struct SystemScreenImageCapturer: ScreenImageCapturing {
    private let cropper: SelectionImageCropper

    public init(cropper: SelectionImageCropper = SelectionImageCropper()) {
        self.cropper = cropper
    }

    public func captureDisplay(displayID: CGDirectDisplayID) -> CGImage? {
        let box = CaptureResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }

            do {
                box.image = try await captureDisplayImage(displayID: displayID)
            } catch {
                box.error = error
            }
        }

        semaphore.wait()

        if let error = box.error {
            Logger.ocr.error(
                "OCR display capture failed (displayID=\(displayID, privacy: .private), reason=\(error.localizedDescription, privacy: .private))"
            )
            return nil
        }

        return box.image
    }

    public func captureRegion(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        displaySizeInPoints: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        guard let fullImage = captureDisplay(displayID: displayID) else {
            return nil
        }

        let cropped = cropper.crop(
            image: fullImage,
            selectionInDisplayPoints: rectInDisplayPoints,
            displaySizeInPoints: displaySizeInPoints,
            scale: scale
        )
        if cropped == nil {
            Logger.ocr.error(
                "OCR region crop failed (displayID=\(displayID, privacy: .private), rect=\(String(describing: rectInDisplayPoints), privacy: .private), displaySize=\(String(describing: displaySizeInPoints), privacy: .private), imagePixels=\(fullImage.width, privacy: .private)x\(fullImage.height, privacy: .private), scale=\(scale, privacy: .private))"
            )
        }
        return cropped
    }

    private func captureDisplayImage(displayID: CGDirectDisplayID) async throws -> CGImage? {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            Logger.ocr.error("OCR display not found (displayID=\(displayID, privacy: .private))")
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        // SCDisplay dimensions are in points, while SCStreamConfiguration expects pixels.
        // Capture at native pixel size to avoid blurry static snapshots on Retina/scaled displays.
        let captureSize = captureSizeInPixels(for: display)
        configuration.width = captureSize.width
        configuration.height = captureSize.height
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func captureSizeInPixels(for display: SCDisplay) -> (width: Int, height: Int) {
        let fallbackWidth = max(display.width, 1)
        let fallbackHeight = max(display.height, 1)

        guard let mode = CGDisplayCopyDisplayMode(display.displayID) else {
            return (fallbackWidth, fallbackHeight)
        }

        let modeWidthInPoints = max(mode.width, 1)
        let modeHeightInPoints = max(mode.height, 1)
        let scaleX = CGFloat(mode.pixelWidth) / CGFloat(modeWidthInPoints)
        let scaleY = CGFloat(mode.pixelHeight) / CGFloat(modeHeightInPoints)
        let resolvedScaleX = scaleX.isFinite && scaleX > 0 ? scaleX : 1
        let resolvedScaleY = scaleY.isFinite && scaleY > 0 ? scaleY : 1

        let pixelWidth = max(
            Int((CGFloat(display.width) * resolvedScaleX).rounded(.toNearestOrAwayFromZero)),
            fallbackWidth
        )
        let pixelHeight = max(
            Int((CGFloat(display.height) * resolvedScaleY).rounded(.toNearestOrAwayFromZero)),
            fallbackHeight
        )
        return (pixelWidth, pixelHeight)
    }
}

private final class CaptureResultBox: @unchecked Sendable {
    var image: CGImage?
    var error: Error?
}
