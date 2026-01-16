import XCTest

@testable import ClipboardMac

final class ItemCardRowPaginationTests: XCTestCase {
    func testIsEnabledRespectsThresholdAndReordering() {
        XCTAssertFalse(ItemCardRowPagination.isEnabled(totalCount: 100, isReorderingEnabled: false))
        XCTAssertTrue(ItemCardRowPagination.isEnabled(totalCount: 101, isReorderingEnabled: false))
        XCTAssertFalse(ItemCardRowPagination.isEnabled(totalCount: 101, isReorderingEnabled: true))
    }

    func testInitialLoadedCount() {
        XCTAssertEqual(ItemCardRowPagination.initialLoadedCount(total: 20, isEnabled: false), 20)
        XCTAssertEqual(ItemCardRowPagination.initialLoadedCount(total: 20, isEnabled: true), 20)
        XCTAssertEqual(ItemCardRowPagination.initialLoadedCount(total: 120, isEnabled: true), 50)
    }

    func testNextLoadedCountPreloadsBeforeEnd() {
        let enabled = true
        XCTAssertEqual(
            ItemCardRowPagination.nextLoadedCount(
                currentLoadedCount: 50,
                visibleIndex: 39,
                totalCount: 120,
                isEnabled: enabled
            ),
            50
        )

        XCTAssertEqual(
            ItemCardRowPagination.nextLoadedCount(
                currentLoadedCount: 50,
                visibleIndex: 40,
                totalCount: 120,
                isEnabled: enabled
            ),
            100
        )

        XCTAssertEqual(
            ItemCardRowPagination.nextLoadedCount(
                currentLoadedCount: 100,
                visibleIndex: 95,
                totalCount: 120,
                isEnabled: enabled
            ),
            120
        )
    }

    func testNextLoadedCountWhenDisabledLoadsAll() {
        XCTAssertEqual(
            ItemCardRowPagination.nextLoadedCount(
                currentLoadedCount: 50,
                visibleIndex: 0,
                totalCount: 120,
                isEnabled: false
            ),
            120
        )
    }

    func testPageForIndex() {
        XCTAssertEqual(ItemCardRowPagination.page(for: 0), 0)
        XCTAssertEqual(ItemCardRowPagination.page(for: 49), 0)
        XCTAssertEqual(ItemCardRowPagination.page(for: 50), 1)
        XCTAssertEqual(ItemCardRowPagination.page(for: 99), 1)
        XCTAssertEqual(ItemCardRowPagination.page(for: 100), 2)
    }
}
