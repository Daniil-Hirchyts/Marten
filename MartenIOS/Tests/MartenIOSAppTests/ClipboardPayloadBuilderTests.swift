@testable import MartenIOSApp
import XCTest

final class ClipboardPayloadBuilderTests: XCTestCase {
    private let builder = ClipboardPayloadBuilder()

    func testFileURLTakesPrecedenceOverWebURLAndCreatesManagedFilePayload() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        let fileData = Data("hello file".utf8)
        try fileData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var content = ClipboardContent()
        content.fileURL = fileURL
        content.webURL = URL(string: "https://example.com")

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .file)
        XCTAssertEqual(payload?.primaryText, fileURL.lastPathComponent)
        XCTAssertEqual(payload?.representations.first?.kind, .custom)
        XCTAssertEqual(payload?.representations.first?.fileExtension, "txt")
        XCTAssertEqual(payload?.representations.first?.data, fileData)
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

    func testImageFileURLBuildsImagePayloadInsteadOfFilePayload() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngFixtureData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        var content = ClipboardContent()
        content.fileURL = imageURL

        let payload = builder.buildPayload(from: content)

        XCTAssertEqual(payload?.itemType, .image)
        XCTAssertEqual(payload?.representations.first?.kind, .png)
        XCTAssertEqual(payload?.representations.first?.fileExtension, "png")
        XCTAssertEqual(payload?.representations.first?.data, pngFixtureData)
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

    private var pngFixtureData: Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+yF9sAAAAASUVORK5CYII="
        )!
    }
}
