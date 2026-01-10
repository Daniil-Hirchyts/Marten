import AppKit
import ClipboardCore
import ClipboardMacServices
import XCTest

@MainActor
final class CapturePipelineIntegrationTests: XCTestCase {
    private var assetBaseURL: URL!

    override func setUp() {
        super.setUp()
        assetBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: assetBaseURL)
        super.tearDown()
    }

    func testPasteboardExtractorToStoreCreatesItemAndThumbnail() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let image = NSImage(size: NSSize(width: 48, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 48, height: 32)).fill()
        image.unlockFocus()

        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let pngData = rep?.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)
        pasteboard.setData(pngData!, forType: .png)

        guard let payload = PasteboardExtractor().extract(from: pasteboard) else {
            XCTFail("Expected payload from pasteboard extractor")
            return
        }

        let persistence = PersistenceController(inMemory: true)
        let assetStore = AssetStore(baseURL: assetBaseURL)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)
        let item = try store.createItem(payload: payload)

        let thumbnailData = ThumbnailGenerator().generateThumbnail(from: pngData!)
        XCTAssertNotNil(thumbnailData)
        if let thumbnailData {
            try store.updateThumbnail(objectID: item.objectID, data: thumbnailData)
        }

        let refreshed = try persistence.viewContext.existingObject(with: item.objectID) as? ClipItem
        XCTAssertEqual(refreshed?.itemTypeValue, .image)
        XCTAssertNotNil(refreshed?.thumbnailPath)
    }
}
