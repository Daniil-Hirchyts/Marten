import AppKit
import ClipboardCore
import XCTest

@testable import ClipboardMac

final class ImageResolutionResolverTests: XCTestCase {
    func testResolveUsesOriginalImageDataBeforeThumbnail() throws {
        let originalData = try makePNGData(width: 300, height: 200)
        let thumbnailPath = try writeTemporaryImage(data: makePNGData(width: 96, height: 64))
        defer { try? FileManager.default.removeItem(atPath: thumbnailPath) }

        let sources: [ImageResolutionResolver.Source] = [
            .init(
                kind: .png,
                binaryData: originalData,
                assetRef: nil,
                fileExtension: "png",
                textData: nil
            )
        ]

        XCTAssertEqual(
            ImageResolutionResolver.resolve(from: sources, thumbnailPath: thumbnailPath),
            "300×200"
        )
    }

    func testResolveUsesFileURLRepresentationWhenImageDataMissing() throws {
        let originalPath = try writeTemporaryImage(data: makePNGData(width: 512, height: 128))
        defer { try? FileManager.default.removeItem(atPath: originalPath) }

        let thumbnailPath = try writeTemporaryImage(data: makePNGData(width: 80, height: 20))
        defer { try? FileManager.default.removeItem(atPath: thumbnailPath) }

        let sources: [ImageResolutionResolver.Source] = [
            .init(
                kind: .fileURL,
                binaryData: nil,
                assetRef: nil,
                fileExtension: nil,
                textData: originalPath.data(using: .utf8)
            )
        ]

        XCTAssertEqual(
            ImageResolutionResolver.resolve(from: sources, thumbnailPath: thumbnailPath),
            "512×128"
        )
    }

    func testResolveFallsBackToThumbnailWhenNoOriginalSourceExists() throws {
        let thumbnailPath = try writeTemporaryImage(data: makePNGData(width: 120, height: 90))
        defer { try? FileManager.default.removeItem(atPath: thumbnailPath) }

        XCTAssertEqual(
            ImageResolutionResolver.resolve(from: [], thumbnailPath: thumbnailPath),
            "120×90"
        )
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "ImageResolutionResolverTests", code: 1)
        }
        return data
    }

    private func writeTemporaryImage(data: Data) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: path)
        return path.path
    }
}
