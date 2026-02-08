import AppKit
import XCTest

@testable import ClipboardMac

final class ThumbnailImageCacheTests: XCTestCase {
    func testSetAndGetImage() {
        let cache = ThumbnailImageCache.shared
        let key = "thumbnail.cache.test.\(UUID().uuidString)"
        let image = NSImage(size: NSSize(width: 8, height: 8))

        cache.setImage(image, forKey: key)

        XCTAssertNotNil(cache.cachedImage(forKey: key))
        XCTAssertFalse(cache.hasMissing(forKey: key))
    }

    func testSetMissingMarksKey() {
        let cache = ThumbnailImageCache.shared
        let key = "thumbnail.cache.missing.\(UUID().uuidString)"

        cache.setMissing(forKey: key)

        XCTAssertTrue(cache.hasMissing(forKey: key))
        XCTAssertNil(cache.cachedImage(forKey: key))
    }
}
