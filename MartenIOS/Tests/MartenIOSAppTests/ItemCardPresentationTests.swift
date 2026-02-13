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
        XCTAssertEqual(presentation.headerSubtitle, "Example")
        XCTAssertEqual(presentation.statsLabel, "\( "Hello from Marten".count) chars")
        XCTAssertEqual(presentation.footerTrailingText, presentation.statsLabel)
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
        XCTAssertEqual(presentation.footerTrailingText, "example.com")
    }

    func testHeaderSubtitlePrefersPrimaryPinboardNameOverSourceApp() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let item = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Pinned item")],
                primaryText: "Pinned item",
                itemType: .text
            ),
            sourceApp: SourceAppInfo(bundleID: "com.example.app", name: "Example"),
            isUserCreated: true
        )

        let pinboard = try store.createPinboard(
            name: "Work",
            colorHex: "#FF9500",
            iconName: "briefcase.fill"
        )
        try store.addItem(objectID: item.objectID, toPinboard: pinboard.objectID)

        let context = persistence.viewContext
        context.refresh(item, mergeChanges: true)
        guard let refreshedItem = try context.existingObject(with: item.objectID) as? ClipItem else {
            XCTFail("Expected refreshed ClipItem")
            return
        }

        let presentation = ItemCardPresentation(item: refreshedItem)
        XCTAssertEqual(presentation.sourceAppDisplayName, "Example")
        XCTAssertEqual(presentation.headerSubtitle, "Work")
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
