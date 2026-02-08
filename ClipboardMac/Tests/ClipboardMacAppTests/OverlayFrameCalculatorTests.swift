import CoreGraphics
import Foundation
import XCTest

@testable import ClipboardMac

final class OverlayFrameCalculatorTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testBottomFrameAnchorsToBottomEdge() {
        let frame = OverlayFrameCalculator.frame(
            visibleFrame: visibleFrame,
            edge: .bottom,
            preferredHorizontalSize: 320,
            preferredVerticalSize: 420
        )

        XCTAssertEqual(frame.minX, 8, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 8, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1424, accuracy: 0.001)
        XCTAssertEqual(frame.height, 320, accuracy: 0.001)
    }

    func testTopFrameAnchorsToTopEdge() {
        let frame = OverlayFrameCalculator.frame(
            visibleFrame: visibleFrame,
            edge: .top,
            preferredHorizontalSize: 320,
            preferredVerticalSize: 420
        )

        XCTAssertEqual(frame.minX, 8, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY - 8, accuracy: 0.001)
        XCTAssertEqual(frame.height, 320, accuracy: 0.001)
    }

    func testLeftAndRightFramesAnchorToCorrectSides() {
        let leftFrame = OverlayFrameCalculator.frame(
            visibleFrame: visibleFrame,
            edge: .left,
            preferredHorizontalSize: 320,
            preferredVerticalSize: 420
        )
        let rightFrame = OverlayFrameCalculator.frame(
            visibleFrame: visibleFrame,
            edge: .right,
            preferredHorizontalSize: 320,
            preferredVerticalSize: 420
        )

        XCTAssertEqual(leftFrame.minX, 8, accuracy: 0.001)
        XCTAssertEqual(leftFrame.minY, 8, accuracy: 0.001)
        XCTAssertEqual(leftFrame.height, visibleFrame.height - 16, accuracy: 0.001)

        XCTAssertEqual(rightFrame.maxX, visibleFrame.maxX - 8, accuracy: 0.001)
        XCTAssertEqual(rightFrame.minY, 8, accuracy: 0.001)
        XCTAssertEqual(rightFrame.height, visibleFrame.height - 16, accuracy: 0.001)
    }

    func testClampsHorizontalAndVerticalSizes() {
        let horizontal = OverlayFrameCalculator.clampedSize(
            preferred: 1_000,
            axis: .horizontal,
            visibleFrame: visibleFrame
        )
        let vertical = OverlayFrameCalculator.clampedSize(
            preferred: 1_000,
            axis: .vertical,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(horizontal, 400, accuracy: 0.001)
        XCTAssertEqual(vertical, 620, accuracy: 0.001)
    }

    func testAnimationOffsetsMatchEdgeDirection() {
        XCTAssertEqual(OverlayFrameCalculator.showOffset(for: .bottom), CGSize(width: 0, height: -16))
        XCTAssertEqual(OverlayFrameCalculator.showOffset(for: .top), CGSize(width: 0, height: 16))
        XCTAssertEqual(OverlayFrameCalculator.showOffset(for: .left), CGSize(width: -16, height: 0))
        XCTAssertEqual(OverlayFrameCalculator.showOffset(for: .right), CGSize(width: 16, height: 0))

        XCTAssertEqual(OverlayFrameCalculator.hideOffset(for: .bottom), CGSize(width: 0, height: -8))
        XCTAssertEqual(OverlayFrameCalculator.hideOffset(for: .top), CGSize(width: 0, height: 8))
        XCTAssertEqual(OverlayFrameCalculator.hideOffset(for: .left), CGSize(width: -8, height: 0))
        XCTAssertEqual(OverlayFrameCalculator.hideOffset(for: .right), CGSize(width: 8, height: 0))
    }
}
