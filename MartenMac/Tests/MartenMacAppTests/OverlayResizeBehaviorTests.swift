import CoreGraphics
import Foundation
import XCTest

@testable import MartenMac

final class OverlayResizeBehaviorTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testTopEdgeResizeKeepsTopAnchoredAndMovesBottomEdge() {
        let original = CGRect(x: 8, y: 572, width: 1424, height: 320)
        let proposedBottom: CGFloat = 500

        let result = OverlayFrameCalculator.resizedFrame(
            from: original,
            visibleFrame: visibleFrame,
            edge: .top,
            proposedEdgePosition: proposedBottom
        )

        XCTAssertEqual(result.frame.maxY, original.maxY, accuracy: 0.001)
        XCTAssertEqual(result.frame.minY, proposedBottom, accuracy: 0.001)
        XCTAssertEqual(result.persistedSize, original.maxY - proposedBottom, accuracy: 0.001)
    }

    func testLeftEdgeResizeKeepsLeftAnchoredAndMovesRightEdge() {
        let original = CGRect(x: 8, y: 8, width: 420, height: 884)
        let proposedRight: CGFloat = 520

        let result = OverlayFrameCalculator.resizedFrame(
            from: original,
            visibleFrame: visibleFrame,
            edge: .left,
            proposedEdgePosition: proposedRight
        )

        XCTAssertEqual(result.frame.minX, original.minX, accuracy: 0.001)
        XCTAssertEqual(result.frame.maxX, proposedRight, accuracy: 0.001)
        XCTAssertEqual(result.persistedSize, proposedRight - original.minX, accuracy: 0.001)
    }

    func testRightEdgeResizeKeepsRightAnchoredAndMovesLeftEdge() {
        let original = CGRect(x: 1012, y: 8, width: 420, height: 884)
        let proposedLeft: CGFloat = 1100

        let result = OverlayFrameCalculator.resizedFrame(
            from: original,
            visibleFrame: visibleFrame,
            edge: .right,
            proposedEdgePosition: proposedLeft
        )

        XCTAssertEqual(result.frame.maxX, original.maxX, accuracy: 0.001)
        XCTAssertEqual(result.frame.minX, proposedLeft, accuracy: 0.001)
        XCTAssertEqual(result.persistedSize, original.maxX - proposedLeft, accuracy: 0.001)
    }

    func testPersistedKeySelectionByOrientation() {
        let suite = "OverlayResizeBehaviorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let settings = OverlayLayoutSettings(userDefaults: defaults)

        settings.setPersistedSize(333, for: .horizontal)
        settings.setPersistedSize(455, for: .vertical)

        XCTAssertEqual(defaults.double(forKey: OverlayLayoutSettings.Keys.overlayHeight), 333, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: OverlayLayoutSettings.Keys.overlayWidth), 455, accuracy: 0.001)
    }
}
