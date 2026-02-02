import AppKit
import XCTest

@testable import ClipboardCore

final class StyledTextContentTests: XCTestCase {
    func testStyledTextContentWithoutTextColorRemovesColorsAndKeepsFormatting() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let attributed = NSMutableAttributedString(string: "Styled")
        attributed.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 22),
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

        guard let styled = item.styledTextContentWithoutTextColor else {
            XCTFail("Expected styled text content")
            return
        }

        XCTAssertEqual(styled.string, "Styled")
        XCTAssertNil(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            styled.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        let font = styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 22, accuracy: 0.5)
    }

    func testRemovingTextColorAttributesRemovesCustomColorAndLinkKeys() {
        let attributed = NSMutableAttributedString(string: "Styled")
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: fullRange
        )
        attributed.addAttribute(
            NSAttributedString.Key("CTForegroundColor"),
            value: NSColor.systemRed.cgColor,
            range: fullRange
        )
        attributed.addAttribute(
            NSAttributedString.Key("CustomLinkTint"),
            value: "link",
            range: fullRange
        )

        let sanitized = attributed.removingTextColorAttributes()

        XCTAssertNil(
            sanitized.attribute(NSAttributedString.Key("CTForegroundColor"), at: 0, effectiveRange: nil)
        )
        XCTAssertNil(
            sanitized.attribute(NSAttributedString.Key("CustomLinkTint"), at: 0, effectiveRange: nil)
        )
        XCTAssertEqual(
            sanitized.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testUpdateRichTextItemKeepsRichRepresentationInSync() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let initial = NSMutableAttributedString(string: "Old")
        let initialRange = NSRange(location: 0, length: initial.length)
        initial.addAttribute(.foregroundColor, value: NSColor.systemRed, range: initialRange)
        let initialRTF = try initial.data(
            from: initialRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload.plainText("Old"),
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: "public.rtf",
                    data: initialRTF,
                    fileExtension: "rtf",
                    displayOrder: 1
                ),
            ],
            primaryText: "Old",
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)

        let updated = NSMutableAttributedString(string: "New")
        let updatedRange = NSRange(location: 0, length: updated.length)
        updated.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: updatedRange
        )
        let updatedRTF = try updated.data(
            from: updatedRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        let saved = try store.updateRichTextItem(
            objectID: item.objectID,
            newText: "New",
            rtfData: updatedRTF
        )

        XCTAssertEqual(saved.primaryText, "New")
        XCTAssertEqual(saved.itemTypeValue, .richText)

        guard
            let richRepresentation = saved.representations?.first(where: { $0.kindValue == .rtf })
        else {
            XCTFail("Expected RTF representation")
            return
        }

        XCTAssertNotNil(richRepresentation.binaryData)
        XCTAssertNil(richRepresentation.textData)

        guard let styled = saved.styledTextContentWithoutTextColor else {
            XCTFail("Expected styled content")
            return
        }
        XCTAssertEqual(styled.string, "New")
        XCTAssertEqual(
            styled.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }
}
