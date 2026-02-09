import MartenCore
import XCTest

@testable import MartenMac

final class ItemEditorAIReplacementTests: XCTestCase {
    func testResolveTargetUsesSelectionForPlainText() {
        let draft = "Hello brave world"
        let selection = nsRange(of: "brave", in: draft)

        let target = ItemEditorAITextEditing.resolveTarget(
            itemType: .text,
            draftText: draft,
            richTextSelection: selection,
            codeSelection: nil
        )

        XCTAssertEqual(target.source, .selection(selection))
        XCTAssertEqual(target.sourceText, "brave")
    }

    func testResolveTargetUsesSelectionForRichText() {
        let draft = "Alpha Beta Gamma"
        let selection = nsRange(of: "Beta", in: draft)

        let target = ItemEditorAITextEditing.resolveTarget(
            itemType: .richText,
            draftText: draft,
            richTextSelection: selection,
            codeSelection: nil
        )

        XCTAssertEqual(target.source, .selection(selection))
        XCTAssertEqual(target.sourceText, "Beta")
    }

    func testResolveTargetUsesCodeSelectionForCodeItems() {
        let draft = "let value = 42"
        let richSelection = nsRange(of: "value", in: draft)
        let codeSelection = nsRange(of: "42", in: draft)

        let target = ItemEditorAITextEditing.resolveTarget(
            itemType: .code,
            draftText: draft,
            richTextSelection: richSelection,
            codeSelection: codeSelection
        )

        XCTAssertEqual(target.source, .selection(codeSelection))
        XCTAssertEqual(target.sourceText, "42")
    }

    func testResolveTargetFallsBackToFullTextWhenSelectionUnavailable() {
        let draft = "No selection here"

        let target = ItemEditorAITextEditing.resolveTarget(
            itemType: .text,
            draftText: draft,
            richTextSelection: nil,
            codeSelection: nil
        )

        XCTAssertEqual(target.source, .fullText)
        XCTAssertEqual(target.sourceText, draft)
    }

    func testApplyReplacementReplacesSelectedRange() throws {
        let draft = "Hello brave world"
        let target = ItemEditorAIResolvedTarget(
            source: .selection(nsRange(of: "brave", in: draft)),
            sourceText: "brave"
        )

        let updated = try ItemEditorAITextEditing.applyReplacement(
            to: draft,
            replacementText: "smart",
            target: target
        )

        XCTAssertEqual(updated, "Hello smart world")
    }

    func testApplyReplacementReplacesFullTextWhenTargetIsFullText() throws {
        let draft = "Original text"
        let target = ItemEditorAIResolvedTarget(source: .fullText, sourceText: draft)

        let updated = try ItemEditorAITextEditing.applyReplacement(
            to: draft,
            replacementText: "New text",
            target: target
        )

        XCTAssertEqual(updated, "New text")
    }

    func testApplyReplacementThrowsForInvalidSelectionRange() {
        let draft = "short"
        let target = ItemEditorAIResolvedTarget(
            source: .selection(NSRange(location: 20, length: 3)),
            sourceText: "invalid"
        )

        XCTAssertThrowsError(
            try ItemEditorAITextEditing.applyReplacement(
                to: draft,
                replacementText: "new",
                target: target
            )
        ) { error in
            XCTAssertEqual(error as? ItemEditorAITextEditingError, .invalidSelectionRange)
        }
    }

    private func nsRange(of substring: String, in text: String) -> NSRange {
        (text as NSString).range(of: substring)
    }
}
