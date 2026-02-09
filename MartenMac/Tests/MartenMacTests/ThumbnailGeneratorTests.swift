import AppKit
import MartenMacServices
import XCTest

@MainActor
final class ThumbnailGeneratorTests: XCTestCase {
    func testGenerateThumbnailReturnsPNGData() throws {
        let image = NSImage(size: NSSize(width: 200, height: 120))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 120)).fill()
        image.unlockFocus()

        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let pngData = rep?.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        let generator = ThumbnailGenerator(maxPixelSize: 80)
        let thumbnail = try generator.generateThumbnail(from: pngData!).get()
        XCTAssertFalse(thumbnail.isEmpty)
    }

    func testGenerateThumbnailWithInvalidDataReturnsError() {
        let generator = ThumbnailGenerator()
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        let result = generator.generateThumbnail(from: invalidData)
        
        switch result {
        case .success:
            XCTFail("Expected failure for invalid image data")
        case .failure(let error):
            XCTAssertEqual(error, .invalidImageData)
        }
    }
}
