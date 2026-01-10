import AppKit
import ClipboardMacServices
import XCTest

@MainActor
final class ThumbnailGeneratorTests: XCTestCase {
    func testGenerateThumbnailReturnsPNGData() {
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
        let thumbnail = generator.generateThumbnail(from: pngData!)
        XCTAssertNotNil(thumbnail)
    }
}
