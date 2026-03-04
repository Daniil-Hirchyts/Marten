import AppKit
import MartenCore
import MartenMacServices
import UniformTypeIdentifiers
import XCTest

@MainActor
final class PasteboardExtractorTests: XCTestCase {
    private struct TestCaptureSettings: CaptureSettingsProviding {
        var ignoreConfidentialContent: Bool
        var ignoreTransientContent: Bool
    }

    func testExtractPlainText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)

        let payload = PasteboardExtractor().extract(from: pasteboard)
        XCTAssertEqual(payload?.itemType, .text)
        XCTAssertEqual(payload?.representations.count, 1)
        XCTAssertEqual(payload?.primaryText, "Hello")
        XCTAssertEqual(payload?.representations.first?.kind, .plainText)
    }

    func testDetectsCodeFromPlainText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("func hello() {\n  print(\"hi\");\n}\n", forType: .string)

        let payload = PasteboardExtractor().extract(from: pasteboard)
        XCTAssertEqual(payload?.itemType, .code)
    }

    func testExtractRichTextAndHtml() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let attributed = NSAttributedString(string: "Rich")
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.setData(rtfData, forType: .rtf)

        let htmlData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        pasteboard.setData(htmlData, forType: .html)

        let payload = PasteboardExtractor().extract(from: pasteboard)
        let kinds = payload?.representations.map { $0.kind } ?? []
        XCTAssertTrue(kinds.contains(.rtf))
        XCTAssertTrue(kinds.contains(.html))
        XCTAssertEqual(payload?.primaryText, "Rich")
        XCTAssertEqual(payload?.itemType, .text)
    }

    func testExtractImage() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let image = NSImage(size: NSSize(width: 60, height: 40))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 60, height: 40)).fill()
        image.unlockFocus()

        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let pngData = rep?.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        pasteboard.setData(pngData!, forType: .png)
        let payload = PasteboardExtractor().extract(from: pasteboard)

        XCTAssertEqual(payload?.itemType, .image)
        XCTAssertTrue(payload?.representations.contains(where: { $0.kind == .png }) ?? false)
    }

    func testExtractJPEGAndPDF() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 50, height: 50)).fill()
        image.unlockFocus()

        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let jpegData = rep?.representation(using: .jpeg, properties: [:])
        XCTAssertNotNil(jpegData)
        pasteboard.setData(jpegData!, forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))

        let payload = PasteboardExtractor().extract(from: pasteboard)
        XCTAssertTrue(payload?.representations.contains(where: { $0.kind == .jpeg }) ?? false)

        pasteboard.clearContents()
        let pdfData = NSData(data: Data(repeating: 1, count: 256))
        pasteboard.setData(pdfData as Data, forType: .pdf)
        let pdfPayload = PasteboardExtractor().extract(from: pasteboard)
        XCTAssertTrue(pdfPayload?.representations.contains(where: { $0.kind == .pdf }) ?? false)
    }

    func testExtractURLAndFileURL() {
        let extractor = PasteboardExtractor()

        let urlPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        urlPasteboard.clearContents()
        urlPasteboard.writeObjects([URL(string: "https://example.com/path")! as NSURL])
        let urlPayload = extractor.extract(from: urlPasteboard)
        XCTAssertEqual(urlPayload?.itemType, .url)
        XCTAssertTrue(urlPayload?.representations.contains(where: { $0.kind == .url }) ?? false)

        let filePasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        filePasteboard.clearContents()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        let fileData = Data("hello mac file".utf8)
        try? fileData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        filePasteboard.writeObjects([fileURL as NSURL])
        let filePayload = extractor.extract(from: filePasteboard)
        XCTAssertEqual(filePayload?.itemType, .file)
        XCTAssertEqual(filePayload?.primaryText, fileURL.lastPathComponent)
        XCTAssertTrue(
            filePayload?.representations.contains(where: { $0.kind == .custom }) ?? false)
        XCTAssertEqual(filePayload?.representations.first?.data, fileData)
    }

    func testFiltersConfidentialContentWhenEnabled() {
        let settings = TestCaptureSettings(
            ignoreConfidentialContent: true, ignoreTransientContent: false)
        let extractor = PasteboardExtractor(settings: settings)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("4242424242424242", forType: .string)

        XCTAssertNil(extractor.extract(from: pasteboard))
    }

    func testDoesNotFilterConfidentialContentWhenDisabled() {
        let settings = TestCaptureSettings(
            ignoreConfidentialContent: false, ignoreTransientContent: false)
        let extractor = PasteboardExtractor(settings: settings)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("4242424242424242", forType: .string)

        let payload = extractor.extract(from: pasteboard)
        XCTAssertEqual(payload?.primaryText, "4242424242424242")
        XCTAssertEqual(payload?.itemType, .text)
    }

    func testFiltersTransientContentWhenEnabled() {
        let settings = TestCaptureSettings(
            ignoreConfidentialContent: false, ignoreTransientContent: true)
        let extractor = PasteboardExtractor(settings: settings)

        let promisedType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)
        pasteboard.setData(
            Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]),
            forType: promisedType)

        XCTAssertNil(extractor.extract(from: pasteboard))
    }
}
