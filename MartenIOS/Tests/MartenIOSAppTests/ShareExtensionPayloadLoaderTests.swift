import MartenCore
@testable import MartenIOSApp
import UniformTypeIdentifiers
import XCTest

final class ShareExtensionPayloadLoaderTests: XCTestCase {
    private let loader = ShareExtensionPayloadLoader()

    func testFileURLCandidateCreatesFilePayload() {
        let candidate = ShareExtensionPayloadCandidate(
            fileURL: URL(fileURLWithPath: "/tmp/example.txt")
        )

        let payload = loader.payload(from: candidate)

        XCTAssertEqual(payload?.itemType, .file)
        XCTAssertEqual(payload?.representations.first?.kind, .fileURL)
    }

    func testWebURLCandidateCreatesURLPayload() {
        let candidate = ShareExtensionPayloadCandidate(
            webURL: URL(string: "https://example.com")!
        )

        let payload = loader.payload(from: candidate)

        XCTAssertEqual(payload?.itemType, .url)
        XCTAssertEqual(payload?.needsLinkPreview, true)
    }

    func testImageCandidateCreatesImagePayload() {
        let candidate = ShareExtensionPayloadCandidate(
            imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            imageUTType: .jpeg
        )

        let payload = loader.payload(from: candidate)

        XCTAssertEqual(payload?.itemType, .image)
        XCTAssertEqual(payload?.representations.first?.kind, .jpeg)
    }

    func testRichTextCandidateCreatesTextPayload() {
        let candidate = ShareExtensionPayloadCandidate(
            rtfData: Data("{\\rtf1\\ansi Test}".utf8),
            plainText: "Test"
        )

        let payload = loader.payload(from: candidate)

        XCTAssertEqual(payload?.itemType, .text)
    }
}
