#if canImport(UIKit)
@testable import MartenIOSApp
import UIKit
import XCTest

final class ItemCardLayoutCalculatorTests: XCTestCase {

    // MARK: - Column count

    func testCompactHorizontalSizeClassProduces2Columns() {
        let traitCollection = UITraitCollection(horizontalSizeClass: .compact)
        XCTAssertEqual(ItemCardLayoutCalculator.columnCount(for: traitCollection), 2)
    }

    func testRegularHorizontalSizeClassProduces3Columns() {
        let traitCollection = UITraitCollection(horizontalSizeClass: .regular)
        XCTAssertEqual(ItemCardLayoutCalculator.columnCount(for: traitCollection), 3)
    }

    func testUnspecifiedHorizontalSizeClassProduces2Columns() {
        let traitCollection = UITraitCollection(horizontalSizeClass: .unspecified)
        XCTAssertEqual(ItemCardLayoutCalculator.columnCount(for: traitCollection), 2)
    }

    // MARK: - Item width clamping

    func testItemWidthClampedToMinimum150() {
        // Very narrow container (e.g. 100pt wide, 2 columns)
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 50, columns: 2)
        XCTAssertEqual(width, 150, "Width should clamp to minimum 150")
    }

    func testItemWidthClampedToMaximum500() {
        // Very wide container (e.g. 2000pt, 2 columns)
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 2000, columns: 2)
        XCTAssertEqual(width, 500, "Width should clamp to maximum 500")
    }

    func testItemWidthNormalRange() {
        // 375pt container, 2 columns, 12pt spacing → rawWidth = (375 - 12) / 2 = 181.5 → floor = 181
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 375, columns: 2)
        XCTAssertEqual(width, 181)
    }

    func testItemWidthNormalRange3Columns() {
        // 768pt container, 3 columns, 12pt spacing → rawWidth = (768 - 24) / 3 = 248 → floor = 248
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 768, columns: 3)
        XCTAssertEqual(width, 248)
    }

    func testItemWidthCustomSpacing() {
        // 400pt container, 2 columns, 16pt spacing → rawWidth = (400 - 16) / 2 = 192 → floor = 192
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 400, columns: 2, spacing: 16)
        XCTAssertEqual(width, 192)
    }

    // MARK: - Width is always floored

    func testItemWidthIsFlooredNotRounded() {
        // 377pt container, 2 columns, 12pt spacing → rawWidth = (377 - 12) / 2 = 182.5 → floor = 182
        let width = ItemCardLayoutCalculator.itemWidth(containerWidth: 377, columns: 2)
        XCTAssertEqual(width, 182)
    }
}
#endif
