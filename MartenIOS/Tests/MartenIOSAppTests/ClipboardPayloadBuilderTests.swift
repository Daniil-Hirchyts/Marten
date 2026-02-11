@testable import MartenIOSApp
import XCTest

final class ClipboardPayloadBuilderTests: XCTestCase {
    private let builder = ClipboardPayloadBuilder()

    func testFileURLTakesPrecedenceOverWebURL() {
        var content = ClipboardContent()
        content.fileURL = URL(fileURLWithPath: "/tmp/test.txt")
        content.webURL = URL(string: "https://example.com")

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .file)
        XCTAssertEqual(payload?.representations.first?.kind, .fileURL)
    }

    func testWebURLCreatesLinkPreviewTarget() {
        var content = ClipboardContent()
        content.webURL = URL(string: "https://example.com/docs")

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .url)
        XCTAssertEqual(payload?.needsLinkPreview, true)
        XCTAssertEqual(payload?.representations.first?.kind, .url)
    }

    func testImagePayloadWinsOverRichAndPlainText() {
        var content = ClipboardContent()
        content.imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        content.rtfData = Data("{\\rtf1 test}".utf8)
        content.plainText = "fallback"

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .image)
        XCTAssertEqual(payload?.representations.first?.kind, .jpeg)
    }

    func testHexTextClassifiesAsColor() {
        var content = ClipboardContent()
        content.plainText = "#FFAA00"

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .color)
    }

    func testCodeLikeTextClassifiesAsCode() {
        var content = ClipboardContent()
        content.plainText = """
        import Foundation
        struct Test {
            let value: String
        }
        """

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .code)
    }
}
