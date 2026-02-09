import AppKit
import MartenCore
import MartenMacServices
import XCTest

final class PasteEngineMartenModeTests: XCTestCase {
    func testCopyItemToMartenWritesPlainText() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Hello")

        let pasteboard = NSPasteboard.withUniqueName()
        let engine = PasteEngine(pasteboard: pasteboard)
        try await engine.copyItemToMarten(item, format: PasteFormat.plainText)
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "Hello")
    }

    func testCopyStackToMartenJoinsItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let stackStore = StackSessionStore(persistence: persistence)
        let session = try stackStore.createSession()
        try stackStore.setEntries(
            sessionID: session.objectID, clipItemIDs: [itemA.objectID, itemB.objectID])
        let pasteboard = NSPasteboard.withUniqueName()
        let engine = PasteEngine(pasteboard: pasteboard)
        try await engine.copyStackToMarten(session)
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "a\nb")
    }

    func testCopyItemToMartenPreservedStripsTextColorButKeepsFormatting() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let attributed = NSMutableAttributedString(string: "Styled")
        attributed.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 24),
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemRed,
            range: NSRange(location: 0, length: attributed.length)
        )

        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: "public.rtf",
                    data: rtfData,
                    fileExtension: "rtf"
                )
            ],
            primaryText: nil,
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)

        let pasteboard = NSPasteboard.withUniqueName()
        let engine = PasteEngine(pasteboard: pasteboard)
        try await engine.copyItemToMarten(item, format: .preserved)

        guard let pastedRTF = pasteboard.data(forType: .rtf) else {
            XCTFail("Expected RTF payload on pasteboard")
            return
        }

        let pasted = try NSAttributedString(
            data: pastedRTF,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )

        XCTAssertEqual(pasted.string, "Styled")
        XCTAssertNil(pasted.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            pasted.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        let font = pasted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 24, accuracy: 0.5)
    }

}
