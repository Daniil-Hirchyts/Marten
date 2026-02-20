@testable import MartenIOSApp
import XCTest

final class ItemCardContextActionTests: XCTestCase {
    func testOrderedActionsMatchCanonicalDefinition() {
        XCTAssertEqual(
            ItemCardContextAction.ordered,
            [
                .copy,
                .copyPlainText,
                .preview,
                .share,
                .moveToPinboard,
                .delete,
            ]
        )
    }

    func testOrderedActionsIncludePinWhenAllowed() {
        XCTAssertEqual(
            ItemCardContextAction.ordered(allowPinning: true),
            [
                .copy,
                .copyPlainText,
                .preview,
                .togglePin,
                .share,
                .moveToPinboard,
                .delete,
            ]
        )
    }

    func testOrderedActionMetadataMatchesCanonicalLabelsAndIcons() {
        let actions = ItemCardContextAction.ordered

        XCTAssertEqual(
            actions.map(\.title),
            [
                "Copy",
                "Copy as Plain Text",
                "Preview",
                "Share",
                "Move to Pinboard",
                "Delete",
            ]
        )
        XCTAssertEqual(
            actions.map(\.systemImage),
            [
                "doc.on.doc",
                "textformat",
                "eye",
                "square.and.arrow.up",
                "circle.dashed",
                "trash",
            ]
        )
        XCTAssertEqual(actions.map(\.isDestructive), [false, false, false, false, false, true])
    }
}
