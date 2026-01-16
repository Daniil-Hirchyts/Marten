import CoreData
import SwiftUI

@MainActor
final class FrameCoordinator: ObservableObject {
    private(set) var capturedPinboardFrames: [NSManagedObjectID: CGRect] = [:]
    private(set) var capturedAllPinboardFrame: CGRect?
    private(set) var capturedPinboardScrollOffset: CGFloat = 0

    private(set) var currentPinboardScrollOffset: CGFloat = 0

    private(set) var latestItemFrames: [NSManagedObjectID: CGRect] = [:]
    private(set) var latestItemRowFrame: CGRect = .zero
    private(set) var dragCenteringOffset: CGSize = .zero

    func updateCapturedPinboardLayout(_ layout: PinboardLayoutInfo) {
        capturedPinboardFrames = layout.overlayPinboardFrames
        capturedAllPinboardFrame = layout.allOverlayFrame
        if let scrollOffset = layout.scrollOffset {
            capturedPinboardScrollOffset = scrollOffset
        }
    }

    func updateCurrentPinboardScrollOffset(_ offset: CGFloat) {
        currentPinboardScrollOffset = offset
    }

    func updateLatestItemFrames(_ frames: [NSManagedObjectID: CGRect]) {
        latestItemFrames = frames
    }

    func updateLatestItemRowFrame(_ frame: CGRect) {
        latestItemRowFrame = frame
    }

    func clearLatestItemFrames() {
        latestItemFrames = [:]
        latestItemRowFrame = .zero
    }

    func setDragCenteringOffset(_ offset: CGSize) {
        dragCenteringOffset = offset
    }
}
