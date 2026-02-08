import XCTest

@testable import ClipboardMac

final class ItemCompactColumnPaginationTests: XCTestCase {
    func testIsEnabledRespectsThresholdAndReordering() {
        XCTAssertFalse(
            ItemCompactColumnPagination.isEnabled(
                totalCount: ItemCompactColumnPagination.thresholdCount,
                isReorderingEnabled: false
            )
        )
        XCTAssertTrue(
            ItemCompactColumnPagination.isEnabled(
                totalCount: ItemCompactColumnPagination.thresholdCount + 1,
                isReorderingEnabled: false
            )
        )
        XCTAssertFalse(
            ItemCompactColumnPagination.isEnabled(
                totalCount: ItemCompactColumnPagination.thresholdCount + 1,
                isReorderingEnabled: true
            )
        )
    }

    func testInitialLoadedCount() {
        XCTAssertEqual(
            ItemCompactColumnPagination.initialLoadedCount(total: 20, isEnabled: false),
            20
        )
        XCTAssertEqual(
            ItemCompactColumnPagination.initialLoadedCount(total: 20, isEnabled: true),
            20
        )
        XCTAssertEqual(
            ItemCompactColumnPagination.initialLoadedCount(total: 200, isEnabled: true),
            ItemCompactColumnPagination.batchSize
        )
    }

    func testNextLoadedCountPreloadsBeforeEnd() {
        let enabled = true
        let start = ItemCompactColumnPagination.batchSize
        let triggerIndex = start - ItemCompactColumnPagination.preloadBuffer

        XCTAssertEqual(
            ItemCompactColumnPagination.nextLoadedCount(
                currentLoadedCount: start,
                visibleIndex: triggerIndex - 1,
                totalCount: 300,
                isEnabled: enabled
            ),
            start
        )

        XCTAssertEqual(
            ItemCompactColumnPagination.nextLoadedCount(
                currentLoadedCount: start,
                visibleIndex: triggerIndex,
                totalCount: 300,
                isEnabled: enabled
            ),
            min(start + ItemCompactColumnPagination.batchSize, 300)
        )
    }

    func testNextLoadedCountWhenDisabledLoadsAll() {
        XCTAssertEqual(
            ItemCompactColumnPagination.nextLoadedCount(
                currentLoadedCount: 50,
                visibleIndex: 0,
                totalCount: 120,
                isEnabled: false
            ),
            120
        )
    }
}
