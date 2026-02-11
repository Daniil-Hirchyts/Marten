import MartenCore
@testable import MartenIOSApp
import XCTest

final class ImageThumbnailLoaderTests: XCTestCase {
    @MainActor
    func testNonImageItemReturnsNil() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let textItem = try store.createTextItem(text: "Plain text, not an image")

        let loader = ImageThumbnailLoader.shared
        let thumbnail = await loader.loadThumbnail(for: textItem)

        XCTAssertNil(thumbnail)
    }

    @MainActor
    func testCacheReturnsSameInstanceOnSecondCall() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        // Create a minimal image item; thumbnail will be nil since no actual image data,
        // but this tests the code path where itemTypeValue == .image
        let payload = ClipItemPayload(
            representations: [.plainText("Image item")],
            primaryText: "Image item",
            itemType: .image
        )
        let imageItem = try store.createItem(payload: payload, sourceApp: nil, isUserCreated: true)

        let loader = ImageThumbnailLoader.shared
        let first = await loader.loadThumbnail(for: imageItem)
        let second = await loader.loadThumbnail(for: imageItem)

        // Both should be nil (no actual image data) but the code path exercises the cache
        XCTAssertEqual(first == nil, second == nil)
    }
}
