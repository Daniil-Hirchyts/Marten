import MartenCore
@testable import MartenIOSApp
import XCTest

final class KeyboardInsertionProjectionTests: XCTestCase {
    func testInsertionTextPrefersPlainText() {
        let summary = SharedClipItemSummary(
            id: UUID(),
            createdAt: Date(),
            itemType: .richText,
            primaryText: "Primary",
            plainText: "Plain",
            sourceAppName: nil,
            sourceAppBundleID: nil,
            pinboardIDs: []
        )

        XCTAssertEqual(summary.insertionText, "Plain")
    }

    func testInsertionTextFallsBackToPrimaryText() {
        let summary = SharedClipItemSummary(
            id: UUID(),
            createdAt: Date(),
            itemType: .text,
            primaryText: "Primary Text",
            plainText: nil,
            sourceAppName: nil,
            sourceAppBundleID: nil,
            pinboardIDs: []
        )

        XCTAssertEqual(summary.insertionText, "Primary Text")
    }
}
