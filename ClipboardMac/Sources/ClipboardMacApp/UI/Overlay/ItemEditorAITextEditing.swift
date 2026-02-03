import ClipboardCore
import Foundation

enum ItemEditorAISelectionSource: Equatable {
    case selection(NSRange)
    case fullText
}

struct ItemEditorAIResolvedTarget: Equatable {
    let source: ItemEditorAISelectionSource
    let sourceText: String
}

enum ItemEditorAITextEditingError: Error, Equatable {
    case invalidSelectionRange
}

enum ItemEditorAITextEditing {
    static func resolveTarget(
        itemType: ItemType,
        draftText: String,
        richTextSelection: NSRange?,
        codeSelection: NSRange?
    ) -> ItemEditorAIResolvedTarget {
        let preferredSelection = preferredSelection(
            itemType: itemType,
            richTextSelection: richTextSelection,
            codeSelection: codeSelection
        )

        if
            let preferredSelection,
            let selectedText = selectedText(in: draftText, range: preferredSelection)
        {
            return ItemEditorAIResolvedTarget(
                source: .selection(preferredSelection),
                sourceText: selectedText
            )
        }

        return ItemEditorAIResolvedTarget(source: .fullText, sourceText: draftText)
    }

    static func applyReplacement(
        to draftText: String,
        replacementText: String,
        target: ItemEditorAIResolvedTarget
    ) throws -> String {
        switch target.source {
        case .fullText:
            return replacementText

        case .selection(let range):
            guard isValidSelectionRange(range, in: draftText) else {
                throw ItemEditorAITextEditingError.invalidSelectionRange
            }
            let nsText = draftText as NSString
            return nsText.replacingCharacters(in: range, with: replacementText)
        }
    }

    static func selectedText(in text: String, range: NSRange) -> String? {
        guard isValidSelectionRange(range, in: text) else { return nil }
        let nsText = text as NSString
        return nsText.substring(with: range)
    }

    private static func preferredSelection(
        itemType: ItemType,
        richTextSelection: NSRange?,
        codeSelection: NSRange?
    ) -> NSRange? {
        switch itemType {
        case .code:
            codeSelection
        case .text, .richText, .url:
            richTextSelection
        default:
            nil
        }
    }

    private static func isValidSelectionRange(_ range: NSRange, in text: String) -> Bool {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0 else {
            return false
        }
        let length = (text as NSString).length
        return NSMaxRange(range) <= length
    }
}
