@testable import MartenIOSApp
import MartenCore
import XCTest

final class ItemCardContextActionTests: XCTestCase {
    func testOrderedActionsMatchCanonicalDefinition() {
        XCTAssertEqual(
            ItemCardContextAction.ordered,
            [
                .copy,
                .copyPlainText,
                .preview,
                .edit,
                .convertType,
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
                .edit,
                .convertType,
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
                "Edit",
                "Convert Type",
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
                "pencil",
                "arrow.triangle.2.circlepath",
                "square.and.arrow.up",
                "circle.dashed",
                "trash",
            ]
        )
        XCTAssertEqual(actions.map(\.isDestructive), [false, false, false, false, false, false, false, true])
    }

    func testConversionTargetsExcludeCurrentType() {
        let targets = ItemCardContextAction.conversionTargets(
            for: .url,
            sourceText: "https://example.com"
        )

        XCTAssertFalse(targets.contains(.url))
        XCTAssertEqual(targets, [.text, .code])
    }

    func testConversionTargetsHideLinkAndColorWhenPatternsAreMissing() {
        let targets = ItemCardContextAction.conversionTargets(
            for: .text,
            sourceText: "Simple note"
        )

        XCTAssertEqual(targets, [.code])
    }

    func testConversionTargetsShowLinkWhenURLPatternExists() {
        let targets = ItemCardContextAction.conversionTargets(
            for: .text,
            sourceText: "example.com"
        )

        XCTAssertEqual(targets, [.url, .code])
    }

    func testConversionTargetsShowColorWhenColorPatternExists() {
        let targets = ItemCardContextAction.conversionTargets(
            for: .text,
            sourceText: "#12ABEF"
        )

        XCTAssertEqual(targets, [.code, .color])
    }

    func testConversionTargetsAreEmptyForUnsupportedTypes() {
        XCTAssertTrue(ItemCardContextAction.conversionTargets(for: .image, sourceText: nil).isEmpty)
        XCTAssertTrue(ItemCardContextAction.conversionTargets(for: .file, sourceText: nil).isEmpty)
        XCTAssertTrue(ItemCardContextAction.conversionTargets(for: .mixed, sourceText: nil).isEmpty)
    }
}
