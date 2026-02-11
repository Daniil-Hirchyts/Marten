@testable import MartenIOSApp
import XCTest

final class RichTextFormattingTransformsTests: XCTestCase {
    func testApplyBulletListAddsPrefixToNonEmptyLines() {
        let input = "First\n\n• Existing\nThird"
        let output = RichTextFormattingTransforms.applyBulletList(to: input)

        XCTAssertEqual(output, "• First\n\n• Existing\n• Third")
    }

    func testApplyNumberedListSkipsEmptyLines() {
        let input = "Alpha\n\nBeta\nGamma"
        let output = RichTextFormattingTransforms.applyNumberedList(to: input)

        XCTAssertEqual(output, "1. Alpha\n\n2. Beta\n3. Gamma")
    }
}
