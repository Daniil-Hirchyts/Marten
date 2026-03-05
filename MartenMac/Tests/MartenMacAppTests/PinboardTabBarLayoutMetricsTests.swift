import XCTest

@testable import MartenMac

final class PinboardTabBarLayoutMetricsTests: XCTestCase {
    func testViewportUsesMeasuredContentWhenItFits() {
        let metrics = PinboardTabBarLayoutMetrics(
            parentWidth: 600,
            addButtonWidth: 30,
            interControlSpacing: 6,
            measuredContentWidth: 180,
            lastNonZeroContentWidth: 0,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )

        XCTAssertEqual(metrics.availableTabsWidth, 564, accuracy: 0.001)
        XCTAssertEqual(metrics.effectiveContentWidth, 180, accuracy: 0.001)
        XCTAssertEqual(metrics.viewportWidth, 200, accuracy: 0.001)
        XCTAssertEqual(metrics.groupWidth, 236, accuracy: 0.001)
        XCTAssertTrue(metrics.isScrollDisabled)
    }

    func testViewportClampsToAvailableWidthWhenContentOverflows() {
        let metrics = PinboardTabBarLayoutMetrics(
            parentWidth: 300,
            addButtonWidth: 30,
            interControlSpacing: 6,
            measuredContentWidth: 400,
            lastNonZeroContentWidth: 0,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )

        XCTAssertEqual(metrics.availableTabsWidth, 264, accuracy: 0.001)
        XCTAssertEqual(metrics.effectiveContentWidth, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.viewportWidth, 264, accuracy: 0.001)
        XCTAssertFalse(metrics.isScrollDisabled)
    }

    func testZeroMeasuredWidthFallsBackToLastNonZeroWidth() {
        let metrics = PinboardTabBarLayoutMetrics(
            parentWidth: 300,
            addButtonWidth: 30,
            interControlSpacing: 6,
            measuredContentWidth: 0,
            lastNonZeroContentWidth: 220,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )

        XCTAssertEqual(metrics.effectiveContentWidth, 220, accuracy: 0.001)
        XCTAssertEqual(metrics.viewportWidth, 240, accuracy: 0.001)
        XCTAssertTrue(metrics.isScrollDisabled)
    }

    func testZeroMeasuredWidthWithoutHistoryUsesDeterministicFallback() {
        let metrics = PinboardTabBarLayoutMetrics(
            parentWidth: 300,
            addButtonWidth: 30,
            interControlSpacing: 6,
            measuredContentWidth: 0,
            lastNonZeroContentWidth: 0,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )

        XCTAssertEqual(metrics.effectiveContentWidth, 120, accuracy: 0.001)
        XCTAssertEqual(metrics.viewportWidth, 140, accuracy: 0.001)
        XCTAssertLessThan(metrics.viewportWidth, metrics.availableTabsWidth)
        XCTAssertTrue(metrics.isScrollDisabled)
    }

    func testWiderAddButtonReducesAvailableTabsWidth() {
        let narrow = PinboardTabBarLayoutMetrics(
            parentWidth: 360,
            addButtonWidth: 30,
            interControlSpacing: 6,
            measuredContentWidth: 500,
            lastNonZeroContentWidth: 0,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )
        let wide = PinboardTabBarLayoutMetrics(
            parentWidth: 360,
            addButtonWidth: 60,
            interControlSpacing: 6,
            measuredContentWidth: 500,
            lastNonZeroContentWidth: 0,
            scrollContentPadding: 10,
            fallbackContentWidth: 120
        )

        XCTAssertEqual(narrow.availableTabsWidth, 324, accuracy: 0.001)
        XCTAssertEqual(wide.availableTabsWidth, 294, accuracy: 0.001)
        XCTAssertEqual(narrow.viewportWidth, 324, accuracy: 0.001)
        XCTAssertEqual(wide.viewportWidth, 294, accuracy: 0.001)
        XCTAssertFalse(narrow.isScrollDisabled)
        XCTAssertFalse(wide.isScrollDisabled)
    }
}
