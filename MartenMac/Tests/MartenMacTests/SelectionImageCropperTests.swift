import CoreGraphics
import XCTest

@testable import MartenMacServices

final class SelectionImageCropperTests: XCTestCase {
    private let cropper = SelectionImageCropper()

    func testPixelRectConvertsPointRectWithYAxisFlip() {
        let rect = cropper.pixelRect(
            for: CGRect(x: 10, y: 5, width: 20, height: 10),
            displaySizeInPoints: CGSize(width: 100, height: 50),
            scale: 2,
            imageSizeInPixels: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 70, width: 40, height: 20))
    }

    func testPixelRectClampsOutOfBoundsSelection() {
        let rect = cropper.pixelRect(
            for: CGRect(x: -10, y: -5, width: 40, height: 20),
            displaySizeInPoints: CGSize(width: 100, height: 50),
            scale: 2,
            imageSizeInPixels: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 70, width: 60, height: 30))
    }

    func testCropProducesExpectedDimensions() {
        let image = makeImage(width: 200, height: 100)
        let cropped = cropper.crop(
            image: image,
            selectionInDisplayPoints: CGRect(x: 20, y: 10, width: 30, height: 15),
            displaySizeInPoints: CGSize(width: 100, height: 50),
            scale: 2
        )

        XCTAssertNotNil(cropped)
        XCTAssertEqual(cropped?.width, 60)
        XCTAssertEqual(cropped?.height, 30)
    }

    func testPixelRectUsesImageToDisplayRatioWhenScaleDiffers() {
        let rect = cropper.pixelRect(
            for: CGRect(x: 1200, y: 100, width: 200, height: 100),
            displaySizeInPoints: CGSize(width: 1500, height: 900),
            scale: 2,
            imageSizeInPixels: CGSize(width: 2560, height: 1440)
        )

        XCTAssertEqual(rect, CGRect(x: 2048, y: 1120, width: 342, height: 160))
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
