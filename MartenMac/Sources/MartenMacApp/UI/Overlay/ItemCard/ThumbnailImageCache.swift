import AppKit
import Foundation

final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private var missingKeys: Set<String> = []
    private let lock = NSLock()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func cachedImage(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func hasMissing(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missingKeys.contains(key)
    }

    func setImage(_ image: NSImage, forKey key: String, cost: Int = 0) {
        cache.setObject(image, forKey: key as NSString, cost: max(0, cost))
        lock.lock()
        missingKeys.remove(key)
        lock.unlock()
    }

    func setMissing(forKey key: String) {
        lock.lock()
        missingKeys.insert(key)
        lock.unlock()
    }
}
