import MartenCore
@testable import MartenIOSApp
import XCTest

final class ItemCardPresentationTests: XCTestCase {
    func testTextPresentationUsesSnippetAndSource() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Hello from Marten")],
                primaryText: "Hello from Marten",
                itemType: .text
            ),
            sourceApp: SourceAppInfo(bundleID: "com.example.app", name: "Example"),
            isUserCreated: true
        )

        let presentation = ItemCardPresentation(item: item)

        XCTAssertEqual(presentation.previewKind, .text)
        XCTAssertEqual(presentation.snippet, "Hello from Marten")
        XCTAssertEqual(presentation.footerSource, "Example")
        XCTAssertEqual(presentation.footerTitle, "Hello from Marten")
    }

    func testURLPresentationUsesHostAndPath() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let url = "https://example.com/path/to/page"
        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: "public.url",
                        text: url,
                        displayOrder: 0
                    )
                ],
                primaryText: url,
                itemType: .url,
                needsLinkPreview: true
            ),
            isUserCreated: true
        )

        let presentation = ItemCardPresentation(item: item)

        XCTAssertEqual(presentation.previewKind, .link)
        XCTAssertEqual(presentation.urlHost, "example.com")
        XCTAssertEqual(presentation.urlPath, "/path/to/page")
    }

    func testColorPresentationNormalizesHex() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("0x12abef")],
                primaryText: "0x12abef",
                itemType: .color
            ),
            isUserCreated: true
        )

        let presentation = ItemCardPresentation(item: item)

        XCTAssertEqual(presentation.previewKind, .color)
        XCTAssertEqual(presentation.colorHex, "#12ABEF")
    }
}
