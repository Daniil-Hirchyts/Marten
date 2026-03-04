import AppKit
import MartenCore
import XCTest

@testable import MartenMac

final class ImagePreviewLoadingTests: XCTestCase {
    func testLoaderUsesOriginalAssetForLargeRequest() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let previousStore = AssetStore.shared
        AssetStore.shared = AssetStore(baseURL: tempDir)
        defer { AssetStore.shared = previousStore }

        let originalData = try makePNGData(width: 1600, height: 900)
        let assetRef = try AssetStore.shared.store(data: originalData, fileExtension: "png")

        let request = try makePreviewRequest(
            assetStore: AssetStore.shared,
            sources: [
                ImagePreviewSourceSnapshot(
                    kind: .png,
                    binaryData: nil,
                    assetRef: assetRef,
                    fileExtension: "png",
                    textData: nil
                )
            ],
            requestedPixelSize: 640
        )

        let result = try XCTUnwrap(CardImagePreviewLoader.resolvePreview(for: request))
        XCTAssertEqual(result.source, .assetFileURL)
        XCTAssertEqual(pixelSize(of: result.image).width, 640)
    }

    func testLoaderUsesFileURLRepresentationWhenOriginalAssetMissing() throws {
        let originalPath = try writeTemporaryImage(data: makePNGData(width: 800, height: 600))
        defer { try? FileManager.default.removeItem(atPath: originalPath) }

        let request = try makePreviewRequest(
            sources: [
                ImagePreviewSourceSnapshot(
                    kind: .fileURL,
                    binaryData: nil,
                    assetRef: nil,
                    fileExtension: nil,
                    textData: originalPath.data(using: .utf8)
                )
            ],
            requestedPixelSize: 512
        )

        let result = try XCTUnwrap(CardImagePreviewLoader.resolvePreview(for: request))
        XCTAssertEqual(result.source, .fileURLRepresentation)
        XCTAssertEqual(pixelSize(of: result.image).width, 512)
    }

    func testLoaderUsesInlineDataWhenNoFileBackedSourceExists() throws {
        let request = try makePreviewRequest(
            sources: [
                ImagePreviewSourceSnapshot(
                    kind: .png,
                    binaryData: try makePNGData(width: 1200, height: 800),
                    assetRef: nil,
                    fileExtension: "png",
                    textData: nil
                )
            ],
            requestedPixelSize: 384
        )

        let result = try XCTUnwrap(CardImagePreviewLoader.resolvePreview(for: request))
        XCTAssertEqual(result.source, .inlineData)
        XCTAssertEqual(pixelSize(of: result.image).width, 384)
    }

    func testLoaderReturnsNilWhenOnlyThumbnailPathExists() throws {
        let request = try makePreviewRequest(
            sources: [],
            requestedPixelSize: 320
        )

        XCTAssertNil(CardImagePreviewLoader.resolvePreview(for: request))
    }

    func testImagePreviewRequestCacheKeyChangesAcrossSizeBuckets() throws {
        let sources = [
            ImagePreviewSourceSnapshot(
                kind: .png,
                binaryData: try makePNGData(width: 1024, height: 768),
                assetRef: nil,
                fileExtension: "png",
                textData: nil
            )
        ]

        let smallRequest = try makePreviewRequest(
            itemID: UUID(),
            sources: sources,
            requestedPixelSize: 190
        )
        let largeRequest = ImagePreviewRequest(
            itemID: smallRequest.itemID,
            objectID: smallRequest.objectID,
            modifiedAt: smallRequest.modifiedAt,
            sources: sources,
            requestedPixelSize: 260
        )

        XCTAssertNotEqual(smallRequest.cacheKey, largeRequest.cacheKey)
        XCTAssertEqual(smallRequest.cachePixelSize, 192)
        XCTAssertEqual(largeRequest.cachePixelSize, 320)
    }

    func testLoaderCachesSeparateImagesAcrossSizeBuckets() throws {
        let sources = [
            ImagePreviewSourceSnapshot(
                kind: .png,
                binaryData: try makePNGData(width: 1600, height: 900),
                assetRef: nil,
                fileExtension: "png",
                textData: nil
            )
        ]

        let itemID = UUID()
        let smallRequest = try makePreviewRequest(
            itemID: itemID,
            sources: sources,
            requestedPixelSize: 180
        )
        let largeRequest = ImagePreviewRequest(
            itemID: itemID,
            objectID: smallRequest.objectID,
            modifiedAt: smallRequest.modifiedAt,
            sources: sources,
            requestedPixelSize: 360
        )

        _ = try XCTUnwrap(CardImagePreviewLoader.shared.loadPreview(for: smallRequest))
        _ = try XCTUnwrap(CardImagePreviewLoader.shared.loadPreview(for: largeRequest))

        let cachedSmall = try XCTUnwrap(ThumbnailImageCache.shared.cachedImage(forKey: smallRequest.cacheKey))
        let cachedLarge = try XCTUnwrap(ThumbnailImageCache.shared.cachedImage(forKey: largeRequest.cacheKey))

        XCTAssertNotEqual(smallRequest.cacheKey, largeRequest.cacheKey)
        XCTAssertLessThan(pixelSize(of: cachedSmall).width, pixelSize(of: cachedLarge).width)
    }

    private func makePreviewRequest(
        itemID: UUID = UUID(),
        assetStore: AssetStore = .shared,
        sources: [ImagePreviewSourceSnapshot],
        requestedPixelSize: Int
    ) throws -> ImagePreviewRequest {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence, assetStore: assetStore)
        let placeholderItem = try store.createTextItem(text: UUID().uuidString)

        return ImagePreviewRequest(
            itemID: itemID,
            objectID: placeholderItem.objectID,
            modifiedAt: Date(),
            sources: sources,
            requestedPixelSize: requestedPixelSize
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
            throw NSError(domain: "ImagePreviewLoadingTests", code: 1)
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

    private func pixelSize(of image: NSImage) -> CGSize {
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if
            let bestRepresentation = bitmapRepresentations.max(
                by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }
            )
        {
            return CGSize(width: bestRepresentation.pixelsWide, height: bestRepresentation.pixelsHigh)
        }

        return image.size
    }

}
