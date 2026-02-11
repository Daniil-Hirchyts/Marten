@testable import MartenIOSApp
import XCTest

final class CodeSyntaxHighlighterTests: XCTestCase {
    func testTokenizeRecognizesTokenKinds() {
        let source = """
        // comment
        let value = 42
        print("hello")
        """

        let tokens = CodeSyntaxHighlighter.tokenize(source)
        let kinds = Set(tokens.map(\.kind))

        XCTAssertTrue(kinds.contains(.comment))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.punctuation))
    }
}
